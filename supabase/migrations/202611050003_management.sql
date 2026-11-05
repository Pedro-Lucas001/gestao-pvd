begin;
alter table public.orders add column subtotal_cents int;
update public.orders set subtotal_cents=total_cents;
alter table public.orders add column discount_cents int not null default 0 check(discount_cents>=0);
alter table public.orders add constraint order_amounts check(subtotal_cents>0 and total_cents=subtotal_cents-discount_cents and total_cents>0);
alter table public.orders add column fulfillment_state text not null default 'waiting' check(fulfillment_state in ('waiting','dispatched','delivered'));
create function app_private.order_subtotal() returns trigger language plpgsql set search_path='' as $$
begin if new.subtotal_cents is null then new.subtotal_cents:=new.total_cents; end if;return new;end $$;
create trigger order_subtotal before insert on public.orders for each row execute function app_private.order_subtotal();
alter table public.orders alter column subtotal_cents set not null;
-- Public orders may later be assigned to an authenticated cashier and shift.
alter table public.orders drop constraint orders_check;
alter table public.orders add constraint order_origin_actor check((cashier_id is null)=(shift_id is null) and (source<>'pos' or cashier_id is not null));
alter table public.kitchen_tickets drop constraint kitchen_tickets_status_check;
alter table public.kitchen_tickets add constraint kitchen_ticket_state check(status in ('queued','preparing','ready','cancelled'));

create table public.cash_movements(
 id uuid primary key,shift_id uuid not null references public.shifts(id),actor_id uuid not null references public.profiles(id),
 kind text not null check(kind in ('withdrawal','supply','refund')),amount_cents int not null check(amount_cents>0),
 justification text not null check(length(trim(justification)) between 5 and 500),created_at timestamptz not null default now(),order_id uuid references public.orders(id)
);
create table public.refunds(
 id uuid primary key,order_id uuid not null unique references public.orders(id),payment_id uuid not null references public.payment_attempts(id),
 requested_by uuid not null references public.profiles(id),amount_cents int not null check(amount_cents>0),reason text not null check(length(trim(reason)) between 5 and 500),
 state text not null default 'pending' check(state in ('pending','confirmed','failed')),provider_reference text unique,created_at timestamptz not null default now(),confirmed_at timestamptz
);
create table public.inventory_adjustments(
 id uuid primary key,ingredient_id uuid not null references public.ingredients(id),actor_id uuid not null references public.profiles(id),
 quantity numeric(14,3) not null,reason text not null check(length(trim(reason)) between 5 and 500),created_at timestamptz not null default now()
);
create table public.customer_contacts(
 order_id uuid primary key references public.orders(id),assigned_to uuid references public.profiles(id),
 name text not null,phone text not null default '',address text not null default '',email text not null default '',
 whatsapp_consent boolean not null default false,erased_at timestamptz,created_at timestamptz not null default now()
);
create index contacts_assignment on public.customer_contacts(assigned_to);
create table public.whatsapp_inbox(
 id uuid primary key default gen_random_uuid(),provider_message_id text not null unique,sender text not null,body text not null,
 received_at timestamptz not null default now(),assigned_to uuid references public.profiles(id),closed_at timestamptz
);
create table app_private.message_replies(
 id uuid primary key default gen_random_uuid(),inbox_id uuid not null unique references public.whatsapp_inbox(id),
 state text not null default 'pending' check(state in ('pending','running','delivered','retry','blocked')),attempts int not null default 0,
 next_attempt_at timestamptz not null default now(),lease_until timestamptz,provider_reference text
);
create table app_private.integration_settings(id boolean primary key default true check(id),enabled boolean not null default true);
insert into app_private.integration_settings values(true,true);

create function app_private.audit_sensitive() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='orders' then
  if old.status is distinct from new.status and new.status='cancelled' then perform app_private.log('order.cancelled','order',new.id::text,-old.total_cents); end if;
  if old.discount_cents is distinct from new.discount_cents then perform app_private.log('order.discounted','order',new.id::text,old.discount_cents-new.discount_cents); end if;
 elsif tg_table_name='payment_attempts' then
  if old.status is distinct from new.status and new.status='refunded' then perform app_private.log('payment.refunded','order',new.order_id::text,-new.amount_cents); end if;
 elsif tg_table_name='ingredients' then
  if tg_op='INSERT' then perform app_private.log('ingredient.created','ingredient',new.id::text);
  elsif old.stock is distinct from new.stock then perform set_config('app.audit_quantity',(new.stock-old.stock)::text,true);perform app_private.log('inventory.changed','ingredient',new.id::text,round((new.stock-old.stock)*new.unit_cost_cents)::bigint);perform set_config('app.audit_quantity','',true);
  elsif (old.name,old.unit,old.minimum_stock,old.unit_cost_cents) is distinct from (new.name,new.unit,new.minimum_stock,new.unit_cost_cents) then perform app_private.log('ingredient.updated','ingredient',new.id::text);end if;
 elsif tg_table_name='products' then
  if tg_op='INSERT' then perform app_private.log('product.created','product',new.id,new.price_cents);
  elsif old is distinct from new then perform app_private.log('product.updated','product',new.id,new.price_cents-old.price_cents);end if;
 elsif tg_table_name='cash_movements' then perform app_private.log('cash.'||new.kind,'shift',new.shift_id::text,case when new.kind='supply' then new.amount_cents else -new.amount_cents end);
 elsif tg_table_name='refunds' then
  if tg_op='INSERT' then perform app_private.log('refund.requested','order',new.order_id::text,-new.amount_cents);
  elsif old.state is distinct from new.state then perform app_private.log('refund.'||new.state,'order',new.order_id::text,-new.amount_cents);end if;
 elsif tg_table_name='recipe_items' then
  if tg_op='DELETE' then perform app_private.log('recipe.removed','product',old.product_id);return old;end if;
  perform app_private.log('recipe.saved','product',new.product_id);
 end if;
 return new;
end $$;
create trigger orders_audit after update on public.orders for each row execute function app_private.audit_sensitive();
create trigger payment_audit after update on public.payment_attempts for each row execute function app_private.audit_sensitive();
create trigger ingredient_audit after insert or update on public.ingredients for each row execute function app_private.audit_sensitive();
create trigger product_audit after insert or update on public.products for each row execute function app_private.audit_sensitive();
create trigger cash_audit after insert on public.cash_movements for each row execute function app_private.audit_sensitive();
create trigger refund_audit after insert or update on public.refunds for each row execute function app_private.audit_sensitive();
create trigger recipe_audit after insert or update or delete on public.recipe_items for each row execute function app_private.audit_sensitive();
create trigger cash_immutable before update or delete on public.cash_movements for each row execute function app_private.immutable_log();
create trigger stock_immutable before update or delete on public.stock_movements for each row execute function app_private.immutable_log();
create trigger adjustment_immutable before update or delete on public.inventory_adjustments for each row execute function app_private.immutable_log();

create function public.save_product(p_product jsonb,p_reason text) returns text language plpgsql security definer set search_path='' as $$
declare ident text:=coalesce(nullif(p_product->>'id',''),gen_random_uuid()::text); category text:=p_product->>'category'; modifiers text[];
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 perform app_private.reason(p_reason);
 if category not in ('hamburgueres','dogoes','combos','porcoes','pasteis','coxinhas','bebidas','adicionais') or length(trim(p_product->>'name')) not between 2 and 120 or (p_product->>'price_cents') !~ '^[0-9]+$' then raise exception 'invalid_product';end if;
 modifiers:=array(select jsonb_array_elements_text(coalesce(p_product->'allowed_modifiers','[]')));
 if array_length(modifiers,1)>20 or exists(select 1 from unnest(modifiers) m where length(m)>80) then raise exception 'invalid_modifiers';end if;
 insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers,active)
 values(ident,trim(p_product->>'name'),category,left(coalesce(p_product->>'description',''),1000),(p_product->>'price_cents')::int,(p_product->>'sector')::public.sector,
 '/menu/'||case when category='combos' then 'hamburgueres' else category end||'.svg',modifiers,coalesce((p_product->>'active')::boolean,true))
 on conflict(id) do update set name=excluded.name,category=excluded.category,description=excluded.description,price_cents=excluded.price_cents,sector=excluded.sector,image_path=excluded.image_path,allowed_modifiers=excluded.allowed_modifiers,active=excluded.active;
 return ident;
end $$;
create function public.save_ingredient(p_id uuid,p_name text,p_unit text,p_minimum numeric,p_cost numeric,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare ident uuid:=coalesce(p_id,gen_random_uuid());
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if length(trim(p_name)) not between 2 and 120 or p_minimum::text !~ '^[0-9]+(\.[0-9]{1,3})?$' or p_cost::text !~ '^[0-9]+(\.[0-9]{1,4})?$' then raise exception 'invalid_ingredient';end if;
 if exists(select 1 from public.recipe_items where ingredient_id=ident) and exists(select 1 from public.ingredients where id=ident and unit<>p_unit) then raise exception 'ingredient_unit_in_use';end if;
 insert into public.ingredients(id,name,unit,minimum_stock,unit_cost_cents) values(ident,trim(p_name),p_unit,p_minimum,p_cost)
 on conflict(id) do update set name=excluded.name,unit=excluded.unit,minimum_stock=excluded.minimum_stock,unit_cost_cents=excluded.unit_cost_cents;
 return ident;
end $$;
create function public.adjust_stock(p_id uuid,p_delta numeric,p_reason text,p_key uuid) returns void language plpgsql security definer set search_path='' as $$
declare previous public.inventory_adjustments;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if p_delta is null or p_delta=0 or p_delta::text !~ '^-?[0-9]+(\.[0-9]{1,3})?$' or abs(p_delta)>1000000 then raise exception 'invalid_quantity';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_key::text,4));
 select * into previous from public.inventory_adjustments where id=p_key;
 if found then if (previous.ingredient_id,previous.quantity,previous.reason) is distinct from (p_id,p_delta,trim(p_reason)) then raise exception 'idempotency_conflict';end if;return;end if;
 perform 1 from public.ingredients where id=p_id for update;if not found then raise exception 'ingredient_not_found';end if;
 insert into public.inventory_adjustments values(p_key,p_id,auth.uid(),p_delta,trim(p_reason),now());
 update public.ingredients set stock=stock+p_delta where id=p_id;
end $$;
create function public.save_recipe(p_product text,p_items jsonb,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare item jsonb;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>100 then raise exception 'invalid_recipe';end if;
 perform 1 from public.products where id=p_product for update;if not found then raise exception 'product_not_found';end if;
 delete from public.recipe_items where product_id=p_product;
 for item in select * from jsonb_array_elements(p_items) loop
  if item->>'quantity' !~ '^[0-9]+(\.[0-9]{1,3})?$' then raise exception 'invalid_quantity';end if;
  insert into public.recipe_items values(p_product,(item->>'ingredient_id')::uuid,(item->>'quantity')::numeric);
 end loop;
end $$;
create function public.apply_discount(p_order uuid,p_discount int,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare ord public.orders;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 select * into ord from public.orders where id=p_order for update;
 if not found or ord.status<>'pending_payment' or p_discount<0 or p_discount>=ord.subtotal_cents or exists(select 1 from public.payment_attempts where order_id=p_order) then raise exception 'discount_not_allowed';end if;
 update public.orders set discount_cents=p_discount,total_cents=subtotal_cents-p_discount where id=p_order;
end $$;
revoke execute on function public.cancel_unpaid_order(uuid) from authenticated;
create function public.cancel_unpaid_order(p_order uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare ord public.orders;
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 select * into ord from public.orders where id=p_order and (cashier_id=auth.uid() or app_private.is_admin()) for update;
 if not found then raise exception 'order_unavailable';end if;
 if ord.status='cancelled' then return;end if;
 if ord.status<>'pending_payment' or exists(select 1 from public.payment_attempts where order_id=p_order and status in ('pending','confirmed')) then raise exception 'payment_reconciliation_required';end if;
 update public.orders set status='cancelled' where id=p_order;
end $$;
create function public.cash_summary(p_shift uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare turn public.shifts; paid bigint; movements bigint;
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501';end if;
 select * into turn from public.shifts where id=p_shift and (cashier_id=auth.uid() or app_private.is_admin());if not found then raise exception 'shift_unavailable';end if;
 select coalesce(sum(p.amount_cents),0) into paid from public.payment_attempts p join public.orders o on o.id=p.order_id where o.shift_id=p_shift and p.method='cash' and p.status in ('confirmed','refunded');
 select coalesce(sum(case when kind='supply' then amount_cents else -amount_cents end),0) into movements from public.cash_movements where shift_id=p_shift;
 return jsonb_build_object('opening_cents',turn.opening_cents,'cash_sales_cents',paid,'movements_cents',movements,'expected_cents',turn.opening_cents+paid+movements,'counted_cents',turn.closing_counted_cents,'closed_at',turn.closed_at);
end $$;
create function public.cash_movement(p_shift uuid,p_kind text,p_amount int,p_reason text,p_key uuid) returns void language plpgsql security definer set search_path='' as $$
declare previous public.cash_movements; balance bigint;
begin
 if not app_private.can_operate() or (p_kind='supply' and not app_private.is_admin()) then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if p_kind not in ('withdrawal','supply') or p_amount is null or p_amount<=0 then raise exception 'invalid_cash_movement';end if;
 perform 1 from public.shifts where id=p_shift and cashier_id=auth.uid() and closed_at is null for update;if not found then raise exception 'shift_unavailable';end if;
 select * into previous from public.cash_movements where id=p_key;
 if found then if (previous.shift_id,previous.kind,previous.amount_cents,previous.justification) is distinct from (p_shift,p_kind,p_amount,trim(p_reason)) then raise exception 'idempotency_conflict';end if;return;end if;
 balance:=(public.cash_summary(p_shift)->>'expected_cents')::bigint;
 if p_kind='withdrawal' and p_amount>balance then raise exception 'insufficient_cash';end if;
 insert into public.cash_movements(id,shift_id,actor_id,kind,amount_cents,justification) values(p_key,p_shift,auth.uid(),p_kind,p_amount,trim(p_reason));
end $$;
create function public.request_refund(p_order uuid,p_key uuid,p_reason text) returns public.refunds language plpgsql security definer set search_path='' as $$
declare payment public.payment_attempts; result public.refunds;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 perform 1 from public.orders where id=p_order for update;if not found then raise exception 'order_unavailable';end if;
 select * into result from public.refunds where order_id=p_order;
 if found then if result.reason<>trim(p_reason) then raise exception 'idempotency_conflict';end if;return result;end if;
 select * into payment from public.payment_attempts where order_id=p_order and status='confirmed' for update;if not found then raise exception 'no_confirmed_payment';end if;
 insert into public.refunds(id,order_id,payment_id,requested_by,amount_cents,reason) values(p_key,p_order,payment.id,auth.uid(),payment.amount_cents,trim(p_reason)) returning * into result;
 return result;
end $$;
create function app_private.finish_refund(p_refund uuid,p_reference text) returns void language plpgsql security definer set search_path='' as $$
declare refund public.refunds;
begin
 select * into refund from public.refunds where id=p_refund for update;if not found then raise exception 'refund_unavailable';end if;
 if refund.state='confirmed' then if refund.provider_reference is distinct from p_reference then raise exception 'reference_conflict';end if;return;end if;
 perform app_private.reason(refund.reason);
 update public.payment_attempts set status='refunded' where id=refund.payment_id and status='confirmed';if not found then raise exception 'payment_not_refundable';end if;
 update public.refunds set state='confirmed',provider_reference=p_reference,confirmed_at=now() where id=p_refund;
 update public.orders set status='cancelled' where id=refund.order_id;
 update public.kitchen_tickets set status='cancelled' where order_id=refund.order_id;
 insert into public.integration_outbox(topic,order_id) values('order.refunded',refund.order_id) on conflict do nothing;
end $$;
create function public.refund_cash(p_refund uuid,p_shift uuid) returns void language plpgsql security definer set search_path='' as $$
declare refund public.refunds;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 select * into refund from public.refunds where id=p_refund for update;if not found then raise exception 'refund_unavailable';end if;
 if not exists(select 1 from public.payment_attempts where id=refund.payment_id and method='cash') then raise exception 'cash_only';end if;
 if refund.state='confirmed' then return;end if;
 perform 1 from public.shifts where id=p_shift and cashier_id=auth.uid() and closed_at is null for update;if not found then raise exception 'admin_open_shift_required';end if;
 if (public.cash_summary(p_shift)->>'expected_cents')::bigint<refund.amount_cents then raise exception 'insufficient_cash';end if;
 perform app_private.reason(refund.reason);
 insert into public.cash_movements(id,shift_id,actor_id,kind,amount_cents,justification,order_id) values(refund.id,p_shift,auth.uid(),'refund',refund.amount_cents,refund.reason,refund.order_id);
 perform app_private.finish_refund(refund.id,'cash:'||refund.id);
end $$;
create function public.confirm_provider_refund(p_refund uuid,p_reference text,p_amount int) returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(p_reference,'')='' or p_amount is null or not exists(select 1 from public.refunds r join public.payment_attempts p on p.id=r.payment_id where r.id=p_refund and r.amount_cents=p_amount and p.method<>'cash') then raise exception 'invalid_refund_confirmation';end if;
 perform app_private.finish_refund(p_refund,p_reference);
end $$;

create function public.anonymize_customer(p_order uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 perform 1 from public.orders where id=p_order and status in ('completed','cancelled') for update;if not found then raise exception 'order_still_active';end if;
 update public.customer_contacts set name='Cliente anonimizado',phone='',address='',email='',whatsapp_consent=false,erased_at=now() where order_id=p_order;
 update public.orders set customer='Pedido #'||number,request_body=jsonb_build_object('anonymized',true) where id=p_order;
 perform app_private.log('customer.anonymized','order',p_order::text);
end $$;
create function public.external_order_queue() returns table(id uuid,number bigint,channel text,total_cents int,created_at timestamptz) language plpgsql security definer set search_path='' as $$
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501';end if;
 return query select o.id,o.number,o.channel,o.total_cents,o.created_at from public.orders o where o.source<>'pos' and o.cashier_id is null and o.status not in ('cancelled','completed') order by o.created_at limit 100;
end $$;
create function public.claim_external_order(p_order uuid) returns public.orders language plpgsql security definer set search_path='' as $$
declare turn uuid; ord public.orders;
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501';end if;
 select id into turn from public.shifts where cashier_id=auth.uid() and closed_at is null for update;if turn is null then raise exception 'open_shift_required';end if;
 select * into ord from public.orders where id=p_order for update;
 if not found or ord.source='pos' or ord.status in ('cancelled','completed') then raise exception 'order_unavailable';end if;
 if ord.cashier_id=auth.uid() then return ord;end if;
 if ord.cashier_id is not null then raise exception 'order_already_assigned';end if;
 update public.orders set cashier_id=auth.uid(),shift_id=turn where id=p_order returning * into ord;
 update public.customer_contacts set assigned_to=auth.uid() where order_id=p_order;
 perform app_private.reason('Pedido automático assumido pelo operador de atendimento');
 perform app_private.log('order.claimed','order',p_order::text);
 return ord;
end $$;
create function public.dispatch_order(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501';end if;
 update public.orders set fulfillment_state='dispatched' where id=p_order and channel='delivery' and status='ready' and (cashier_id=auth.uid() or app_private.is_admin());if not found then raise exception 'delivery_not_ready';end if;
 insert into public.integration_outbox(topic,order_id) values('order.dispatched',p_order) on conflict do nothing;
end $$;
create function public.deliver_order(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501';end if;
 update public.orders set fulfillment_state='delivered',status='completed',completed_at=coalesce(completed_at,now()) where id=p_order and status in ('ready','completed') and (cashier_id=auth.uid() or app_private.is_admin());if not found then raise exception 'order_not_ready';end if;
 insert into public.integration_outbox(topic,order_id) values('order.delivered',p_order) on conflict do nothing;
end $$;

alter table public.cash_movements enable row level security;
create policy cash_read on public.cash_movements for select to authenticated using(app_private.is_admin() or (app_private.can_operate() and exists(select 1 from public.shifts where id=shift_id and cashier_id=auth.uid())));
alter table public.refunds enable row level security;
create policy refunds_admin on public.refunds for select to authenticated using(app_private.is_admin());
alter table public.inventory_adjustments enable row level security;
create policy adjustments_admin on public.inventory_adjustments for select to authenticated using(app_private.is_admin());
alter table public.customer_contacts enable row level security;
create policy contact_need_to_know on public.customer_contacts for select to authenticated using(app_private.is_admin() or (app_private.can_operate() and assigned_to=auth.uid() and erased_at is null and exists(select 1 from public.orders where id=order_id and status in ('queued','preparing','ready'))));
alter table public.whatsapp_inbox enable row level security;
create policy inbox_need_to_know on public.whatsapp_inbox for select to authenticated using(app_private.is_admin() or (app_private.can_operate() and assigned_to=auth.uid() and closed_at is null));
grant select on public.cash_movements,public.refunds,public.inventory_adjustments,public.customer_contacts,public.whatsapp_inbox to authenticated;
revoke all on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.role(),app_private.is_admin(),app_private.can_operate(),app_private.terminal_open() to authenticated;
grant execute on function public.save_product(jsonb,text),public.save_ingredient(uuid,text,text,numeric,numeric,text),public.adjust_stock(uuid,numeric,text,uuid),public.save_recipe(text,jsonb,text),public.apply_discount(uuid,int,text),public.cancel_unpaid_order(uuid,text),public.cash_summary(uuid),public.cash_movement(uuid,text,int,text,uuid),public.request_refund(uuid,uuid,text),public.refund_cash(uuid,uuid),public.anonymize_customer(uuid,text),public.external_order_queue(),public.claim_external_order(uuid),public.dispatch_order(uuid),public.deliver_order(uuid) to authenticated;
grant execute on function public.confirm_provider_refund(uuid,text,int) to service_role;
create or replace function app_private.release_order(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare ord public.orders; consumption record;
begin
 perform app_private.reason('Baixa automática por venda confirmada');
 select * into ord from public.orders where id=p_order for update;
 if ord.status<>'pending_payment' then return; end if;
 if not exists(select 1 from public.payment_attempts where order_id=p_order and status='confirmed') then raise exception 'payment_required'; end if;
 -- Stock movements are immutable and unique per sale/ingredient. Negative balances
 -- reflect a real paid sale; administrators must resolve shortages, never hide them.
 perform 1 from public.ingredients where id in(select r.ingredient_id from public.recipe_items r join public.order_items i on i.product_id=r.product_id where i.order_id=p_order) order by id for update;
 for consumption in select r.ingredient_id,sum(r.quantity*i.quantity) quantity from public.recipe_items r join public.order_items i on i.product_id=r.product_id where i.order_id=p_order group by r.ingredient_id loop
  insert into public.stock_movements(order_id,ingredient_id,quantity) values(p_order,consumption.ingredient_id,-consumption.quantity);
  update public.ingredients set stock=stock-consumption.quantity where id=consumption.ingredient_id;
 end loop;
 insert into public.kitchen_tickets(order_id,order_number,customer,sector,items)
 select ord.id,ord.number,ord.customer,i.sector,jsonb_agg(jsonb_build_object('name',i.name,'quantity',i.quantity,'modifiers',i.modifiers,'notes',i.notes) order by i.id)
 from public.order_items i where i.order_id=p_order group by i.sector;
 update public.orders set status='queued',paid_at=now() where id=p_order;
 insert into public.integration_outbox(topic,order_id) values('order.paid',p_order) on conflict do nothing;
end $$;

commit;
