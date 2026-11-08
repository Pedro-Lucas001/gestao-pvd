begin;
-- Entrega: preparo imediato com recebimento pendente; cartão presencial não usa o checkout online.
alter table public.online_shop_settings add column delivery_card_enabled boolean not null default true;
alter table public.online_orders drop constraint online_orders_payment_method_check;
alter table public.online_orders add constraint online_orders_payment_method_check check(payment_method in ('pix','card','cash','card_delivery'));
alter table public.online_payments drop constraint online_payments_method_check;
alter table public.online_payments add constraint online_payments_method_check check(method in ('pix','card','cash','card_delivery'));
alter table public.online_orders add column card_fee_cents int not null default 0 check(card_fee_cents>=0);
alter table public.online_orders add column pay_on_delivery boolean not null default false;
alter table public.online_orders drop constraint online_orders_check;
alter table public.online_orders add constraint online_orders_check check(total_cents=subtotal_cents+delivery_fee_cents+card_fee_cents);
alter table public.online_orders add constraint delivery_payment_scope check(not pay_on_delivery or (fulfillment='delivery' and payment_method in ('pix','cash','card_delivery')));
alter table app_private.online_contacts add column reference text not null default '';
-- O segredo de acompanhamento continua fora de public e das filas da equipe.
create table app_private.online_tracking_links(order_id uuid primary key references public.online_orders(id),token text not null check(token ~ '^[a-f0-9]{64}$'));
revoke all on app_private.online_tracking_links from public,anon,authenticated;

create function app_private.delivery_card_fee(p_base int) returns int language sql immutable set search_path='' as $$
 select ((p_base::bigint*6+50)/100)::int
$$;
revoke all on function app_private.delivery_card_fee(int) from public,anon,authenticated;
create function public.online_delivery_quote(p_items jsonb,p_fulfillment text,p_method text) returns jsonb language plpgsql security definer set search_path='' as $$
declare q jsonb;fee int:=0;
begin
 if p_method is null or p_method not in ('pix','cash','card','card_delivery') then raise exception 'payment_unavailable';end if;
 if p_method='card_delivery' and (p_fulfillment<>'delivery' or not (select delivery_card_enabled from public.online_shop_settings where singleton)) then raise exception 'payment_unavailable';end if;
 q:=public.online_quote(p_items,p_fulfillment);
 if p_method='card_delivery' then fee:=app_private.delivery_card_fee((q->>'total_cents')::int);end if;
 if (q->>'total_cents')::int+fee>1000000 then raise exception 'order_too_large';end if;
 return q||jsonb_build_object('card_fee_cents',fee,'card_fee_percent',case when p_method='card_delivery' then 6 else 0 end,'total_cents',(q->>'total_cents')::int+fee);
end $$;


create or replace function public.online_save_settings(p_settings jsonb,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;perform app_private.reason(p_reason);
 update public.online_shop_settings set enabled=(p_settings->>'enabled')::boolean,delivery_enabled=(p_settings->>'delivery_enabled')::boolean,
 delivery_fee_cents=(p_settings->>'delivery_fee_cents')::int,cash_enabled=(p_settings->>'cash_enabled')::boolean,delivery_card_enabled=coalesce((p_settings->>'delivery_card_enabled')::boolean,delivery_card_enabled),whatsapp_number=coalesce(p_settings->>'whatsapp_number','') where singleton;
 perform app_private.log('online.settings_updated','shop','online');
end $$;

create or replace function public.online_create_order(p_key uuid,p_tracking text,p_items jsonb,p_contact jsonb,p_fulfillment text,p_method text,p_change_for int,p_expected_total int) returns jsonb language plpgsql security definer set search_path='' as $$
declare q jsonb;o public.online_orders;h text;ident uuid;s public.online_shop_settings;
begin
 if p_key is null or p_tracking is null or p_tracking !~ '^[a-f0-9]{64}$' then raise exception 'invalid_tracking_key';end if;
 h:=encode(extensions.digest(jsonb_build_object('items',p_items,'contact',p_contact,'fulfillment',p_fulfillment,'method',p_method,'change_for',p_change_for,'total',p_expected_total)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_key::text,16));
 select * into o from public.online_orders where idempotency_key=p_key;
 if found then
  if o.request_hash<>h or o.token_hash<>encode(extensions.digest(p_tracking,'sha256'),'hex') then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',o.id,'number',o.number,'total_cents',o.total_cents,'status',o.status);
 end if;
 select * into s from public.online_shop_settings where singleton;
 if p_method is null or p_method not in ('pix','card','cash','card_delivery') or (p_method='cash' and not s.cash_enabled) then raise exception 'payment_unavailable';end if;
 if p_contact is null or length(trim(coalesce(p_contact->>'name',''))) not between 2 and 100 or coalesce(p_contact->>'phone','') !~ '^[0-9]{10,15}$' or length(coalesce(p_contact->>'email',''))>254 or length(coalesce(p_contact->>'address',''))>500 then raise exception 'invalid_contact';end if;
 if (p_method in ('pix','card') or coalesce(p_contact->>'email','')<>'') and coalesce(p_contact->>'email','') !~ '^[^ @]+@[^ @]+\.[^ @]+$' then raise exception 'email_required';end if;
 if p_fulfillment='delivery' and length(trim(coalesce(p_contact->>'address','')))<10 then raise exception 'delivery_contact_required';end if;
 if length(coalesce(p_contact->>'reference',''))>200 or (p_fulfillment='delivery' and length(trim(coalesce(p_contact->>'reference','')))<2) then raise exception 'delivery_reference_required';end if;
 q:=public.online_delivery_quote(p_items,p_fulfillment,p_method);
 if p_expected_total is null or p_expected_total<>(q->>'total_cents')::int then raise exception 'price_changed_review_order';end if;
 if p_change_for is not null and (p_method<>'cash' or p_change_for<p_expected_total or p_change_for>1000000) then raise exception 'invalid_change_amount';end if;
 insert into public.online_orders(token_hash,idempotency_key,request_hash,status,fulfillment,payment_method,items,subtotal_cents,delivery_fee_cents,total_cents,cash_change_for_cents,card_fee_cents,pay_on_delivery,cash_authorized)
 values(encode(extensions.digest(p_tracking,'sha256'),'hex'),p_key,h,case when p_method='cash' then 'awaiting_store' else 'payment_pending' end,p_fulfillment,p_method,q->'items',(q->>'subtotal_cents')::int,(q->>'delivery_fee_cents')::int,p_expected_total,p_change_for,(q->>'card_fee_cents')::int,p_fulfillment='delivery' and p_method<>'card',p_fulfillment='delivery' and p_method='cash') returning * into o;
 insert into app_private.online_contacts(order_id,name,phone,email,address,whatsapp_consent,reference) values(o.id,trim(p_contact->>'name'),p_contact->>'phone',coalesce(p_contact->>'email',''),coalesce(p_contact->>'address',''),coalesce((p_contact->>'whatsapp_consent')::boolean,false),trim(coalesce(p_contact->>'reference','')));
 insert into app_private.online_tracking_links values(o.id,p_tracking);
 insert into public.online_notifications(order_id,topic,revision) values(o.id,'order.received',o.revision);
 if o.pay_on_delivery then perform app_private.online_release(o.id);select * into o from public.online_orders where id=o.id;end if;
 if p_method='pix' then insert into public.online_notifications(order_id,topic,revision) values(o.id,'order.payment_requested',o.revision);end if;
 return jsonb_build_object('id',o.id,'number',o.number,'total_cents',o.total_cents,'status',o.status);
end $$;

create or replace function app_private.online_release(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare o public.online_orders;r record;previous numeric;delta numeric;cost numeric;seen uuid[]:='{}';jobsector public.sector;snapshot jsonb;
begin
 select * into o from public.online_orders where id=p_order for update;
 if o.status in ('cancelled','completed','dispatched','ready') then return;end if;
 if o.paid_cents<o.total_cents and not (o.payment_method='cash' and o.cash_authorized) and not o.pay_on_delivery then raise exception 'payment_required';end if;
 if exists(select 1 from public.online_kitchen_jobs where order_id=o.id and revision=o.revision) then return;end if;
 perform app_private.reason('Baixa de insumos do pedido online '||o.number::text);
 for r in
  with lines as(select line_no,item->>'product_id' product_id,(item->>'quantity')::int quantity,item->'modifiers' modifiers from jsonb_array_elements(o.items) with ordinality x(item,line_no)),opts as(
   select l.line_no,l.product_id,l.quantity,l.modifiers,ri.ingredient_id from lines l join public.recipe_items ri on ri.product_id=l.product_id
   union select l.line_no,l.product_id,l.quantity,l.modifiers,m.ingredient_id from lines l join public.recipe_modifier_rules m on m.product_id=l.product_id and l.modifiers ? m.modifier
  ) select op.ingredient_id,sum(op.quantity*greatest(0,coalesce((select ri.quantity from public.recipe_items ri where ri.product_id=op.product_id and ri.ingredient_id=op.ingredient_id),0)+coalesce((select sum(m.quantity_delta) from public.recipe_modifier_rules m where m.product_id=op.product_id and m.ingredient_id=op.ingredient_id and op.modifiers ? m.modifier),0))) quantity from opts op group by op.ingredient_id order by op.ingredient_id
 loop
  seen:=array_append(seen,r.ingredient_id);
  select quantity into previous from app_private.online_allocations where order_id=o.id and ingredient_id=r.ingredient_id;
  delta:=r.quantity-coalesce(previous,0);
  if delta>0 then
   select unit_cost_cents into cost from public.ingredients where id=r.ingredient_id for update;
   insert into public.online_stock_movements(order_id,revision,ingredient_id,quantity,unit_cost_cents) values(o.id,o.revision,r.ingredient_id,-delta,cost);
   update public.ingredients set stock=stock-delta where id=r.ingredient_id;
  end if;
  insert into app_private.online_allocations values(o.id,r.ingredient_id,r.quantity) on conflict(order_id,ingredient_id) do update set quantity=excluded.quantity;
 end loop;
 update app_private.online_allocations a set quantity=0 where a.order_id=o.id and not(a.ingredient_id=any(seen));
 delete from public.online_kitchen_jobs j where j.order_id=o.id and not exists(select 1 from jsonb_array_elements(o.items) i where (i->>'sector')::public.sector=j.sector);
 for jobsector in select distinct (i->>'sector')::public.sector from jsonb_array_elements(o.items) i loop
  select jsonb_agg(i-'unit_price_cents'-'name') into snapshot from jsonb_array_elements(o.items) i where (i->>'sector')::public.sector=jobsector;
  insert into public.online_kitchen_jobs(order_id,sector,revision,items_snapshot,status) values(o.id,jobsector,o.revision,snapshot,'queued') on conflict(order_id,sector) do update set revision=excluded.revision,items_snapshot=excluded.items_snapshot,status=case when online_kitchen_jobs.items_snapshot=excluded.items_snapshot then online_kitchen_jobs.status else 'queued' end,updated_at=now();
 end loop;
 update public.online_orders set status=case when not exists(select 1 from public.online_kitchen_jobs where order_id=o.id and status<>'ready') then 'ready' when exists(select 1 from public.online_kitchen_jobs where order_id=o.id and status='preparing') then 'preparing' else 'accepted' end,updated_at=now(),paid_at=case when paid_cents>=total_cents then coalesce(paid_at,now()) else paid_at end where id=o.id;
 insert into public.online_notifications(order_id,topic,revision) values(o.id,case when o.paid_cents>=o.total_cents then 'order.paid' when o.pay_on_delivery then 'order.delivery_accepted' else 'order.cash_accepted' end,o.revision) on conflict do nothing;
end $$;

create or replace function app_private.online_payment(p_order uuid,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.online_orders;p public.online_payments;c app_private.online_contacts;
begin
 select * into o from public.online_orders where id=p_order for update;
 if not found or not (o.status='payment_pending' or (o.pay_on_delivery and o.status in ('accepted','preparing','ready','dispatched'))) or o.payment_method not in ('pix','card') or o.total_cents<=o.paid_cents then raise exception 'payment_not_allowed';end if;
 select * into p from public.online_payments where id=p_key;
 if found and (p.order_id<>o.id or p.revision<>o.revision) then raise exception 'idempotency_conflict';end if;
 select * into p from public.online_payments where order_id=o.id and status='pending';
 if not found then insert into public.online_payments(id,order_id,revision,method,amount_cents) values(p_key,o.id,o.revision,o.payment_method,o.total_cents-o.paid_cents) returning * into p;end if;
 select * into c from app_private.online_contacts where order_id=o.id;
 return jsonb_build_object('id',p.id,'order_id',o.id,'number',o.number,'amount_cents',p.amount_cents,'method',p.method,'status',p.status,'creation_state',p.creation_state,'provider_reference',p.provider_reference,'checkout_url',p.checkout_url,'pix_code',p.pix_code,'expires_at',p.expires_at,'email',c.email);
end $$;

create or replace function public.online_request_change(p_tracking text,p_key uuid,p_items jsonb,p_reason text,p_expected_total int) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.online_orders;q jsonb;c public.online_changes;h text;sectors public.sector[];
begin
 o:=app_private.online_resolve(p_tracking);select * into o from public.online_orders where id=o.id for update;
 h:=encode(extensions.digest(jsonb_build_object('items',p_items,'reason',p_reason,'total',p_expected_total)::text,'sha256'),'hex');
 select * into c from public.online_changes where id=p_key;
 if found then if c.order_id<>o.id or c.request_hash<>h then raise exception 'idempotency_conflict';end if;return c.id;end if;
 if o.status not in ('accepted','preparing') or exists(select 1 from public.online_payments where order_id=o.id and status='pending') then raise exception 'change_not_allowed';end if;
 if length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'change_reason_required';end if;
 q:=app_private.online_items(p_items);q:=q||jsonb_build_object('total_cents',(q->>'subtotal_cents')::int+o.delivery_fee_cents+case when o.payment_method='card_delivery' then app_private.delivery_card_fee((q->>'subtotal_cents')::int+o.delivery_fee_cents) else o.card_fee_cents end);
 if p_expected_total is null or p_expected_total<>(q->>'total_cents')::int then raise exception 'price_changed_review_order';end if;
 select array_agg(distinct (i->>'sector')::public.sector) into sectors from jsonb_array_elements(o.items||(q->'items')) i;
 insert into public.online_changes(id,order_id,request_hash,base_revision,items,total_cents,subtotal_cents,reason,sectors)
 values(p_key,o.id,h,o.revision,q->'items',p_expected_total,(q->>'subtotal_cents')::int,trim(p_reason),sectors);
 return p_key;
end $$;

create or replace function public.online_change_quote(p_tracking text,p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.online_orders;q jsonb;
begin
 o:=app_private.online_resolve(p_tracking);q:=app_private.online_items(p_items);
 return q||jsonb_build_object('delivery_fee_cents',o.delivery_fee_cents,'card_fee_cents',case when o.payment_method='card_delivery' then app_private.delivery_card_fee((q->>'subtotal_cents')::int+o.delivery_fee_cents) else o.card_fee_cents end,'total_cents',(q->>'subtotal_cents')::int+o.delivery_fee_cents+case when o.payment_method='card_delivery' then app_private.delivery_card_fee((q->>'subtotal_cents')::int+o.delivery_fee_cents) else o.card_fee_cents end);
end $$;

create or replace function public.online_review_change(p_change uuid,p_accept boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare c public.online_changes;o public.online_orders;sector public.sector;
begin
 select * into c from public.online_changes where id=p_change for update;if not found then raise exception 'change_unavailable';end if;
 if not (app_private.is_admin() or coalesce(app_private.role()='kitchen' and app_private.terminal_open() and (select p.sector from public.profiles p where p.id=auth.uid())=any(c.sectors),false)) then raise exception 'access_denied' using errcode='42501';end if;
 if c.status<>'requested' then return;end if;
 if p_accept is null or length(trim(coalesce(p_reason,''))) not between 5 and 500 then raise exception 'review_reason_required';end if;
 select * into o from public.online_orders where id=c.order_id for update;
 if o.revision<>c.base_revision or o.status not in ('accepted','preparing') then raise exception 'change_stale';end if;
 perform app_private.reason(p_reason);
 if not p_accept then update public.online_changes set status='rejected',review_reason=trim(p_reason),reviewed_by=auth.uid(),reviewed_at=now() where id=c.id;
  insert into public.online_notifications(order_id,topic,revision) values(o.id,'change.rejected:'||c.id,o.revision) on conflict do nothing;perform app_private.log('online.change_rejected','online_order',o.id::text);return;end if;
 if app_private.is_admin() then
  insert into app_private.online_change_votes select c.id,s,auth.uid() from unnest(c.sectors) s on conflict do nothing;
 else
  select p.sector into sector from public.profiles p where p.id=auth.uid();
  insert into app_private.online_change_votes values(c.id,sector,auth.uid()) on conflict do nothing;
 end if;
 if exists(select 1 from unnest(c.sectors) s where not exists(select 1 from app_private.online_change_votes v where v.change_id=c.id and v.sector=s)) then perform app_private.log('online.change_sector_approved','online_order',o.id::text);return;end if;
 update public.online_changes set status='accepted',review_reason=trim(p_reason),reviewed_by=auth.uid(),reviewed_at=now() where id=c.id;
 update public.online_orders set items=c.items,subtotal_cents=c.subtotal_cents,total_cents=c.total_cents,card_fee_cents=c.total_cents-c.subtotal_cents-delivery_fee_cents,pay_on_delivery=case when paid_cents>0 and c.total_cents>paid_cents then false else pay_on_delivery end,revision=revision+1,updated_at=now(),
 payment_method=case when paid_cents>0 and c.total_cents>paid_cents then 'pix' else payment_method end,
 status=case when c.total_cents>paid_cents and not((payment_method='cash' and cash_authorized or pay_on_delivery) and paid_cents=0) then 'payment_pending' else 'accepted' end where id=o.id;
 if c.total_cents<=o.paid_cents or ((o.payment_method='cash' and o.cash_authorized or o.pay_on_delivery) and o.paid_cents=0) then perform app_private.online_release(o.id);end if;
 insert into public.online_notifications(order_id,topic,revision) values(o.id,'change.accepted',o.revision+1) on conflict do nothing;
 perform app_private.reason(p_reason);perform app_private.log('online.change_accepted','online_order',o.id::text,c.total_cents-o.total_cents);
end $$;

create or replace function public.online_claim_notifications() returns jsonb language plpgsql security definer set search_path='' as $$
declare job record;result jsonb:='[]';payment jsonb;
begin
 update public.online_notifications n set delivered_at=now(),last_error='superseded' from public.online_orders o where o.id=n.order_id and (n.revision<o.revision or (n.topic='order.payment_requested' and o.status='cancelled')) and n.delivered_at is null;
 for job in
  with picked as(select n.id from public.online_notifications n join app_private.online_contacts c on c.order_id=n.order_id where n.delivered_at is null and n.attempts<8 and n.next_attempt_at<=now() and (n.lease_until is null or n.lease_until<now()) and c.whatsapp_consent order by n.next_attempt_at for update of n skip locked limit 2),claimed as(update public.online_notifications set lease_until=now()+interval '2 minutes',attempts=attempts+1 where id in(select id from picked) returning *)
  select n.*,o.number,o.status,o.payment_method,greatest(0,o.total_cents-o.paid_cents) due_cents,c.phone from claimed n join public.online_orders o on o.id=n.order_id join app_private.online_contacts c on c.order_id=n.order_id
 loop
  payment:=null;
  if job.topic in ('change.accepted','order.payment_requested') and job.due_cents>0 and job.status in ('payment_pending','accepted','preparing','ready','dispatched') and job.payment_method='pix' then payment:=app_private.online_payment(job.order_id,job.id);end if;
  result:=result||jsonb_build_array(jsonb_build_object('id',job.id,'topic',job.topic,'number',job.number,'due_cents',job.due_cents,'phone',job.phone,'payment',payment,'tracking', (select token from app_private.online_tracking_links where order_id=job.order_id),'within_window',exists(select 1 from public.whatsapp_inbox i where i.sender=job.phone and i.received_at>now()-interval '23 hours')));
 end loop;return result;
end $$;

create or replace function public.online_order_status(p_tracking text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.online_orders;changes jsonb;payments jsonb;
begin
 o:=app_private.online_resolve(p_tracking);
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'status',c.status,'reason',c.reason,'review_reason',c.review_reason,'total_cents',c.total_cents,'created_at',c.created_at,'sectors',c.sectors,'approved_sectors',(select coalesce(jsonb_agg(v.sector),'[]') from app_private.online_change_votes v where v.change_id=c.id)) order by c.created_at desc),'[]') into changes from public.online_changes c where c.order_id=o.id;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'method',p.method,'provider',p.provider,'status',p.status,'amount_cents',p.amount_cents,'pix_code',p.pix_code,'expires_at',p.expires_at,'checkout_url',p.checkout_url) order by p.created_at desc),'[]') into payments from public.online_payments p where p.order_id=o.id;
 return jsonb_build_object('id',o.id,'number',o.number,'status',o.status,'fulfillment',o.fulfillment,'items',o.items,'revision',o.revision,'subtotal_cents',o.subtotal_cents,'delivery_fee_cents',o.delivery_fee_cents,'total_cents',o.total_cents,'paid_cents',o.paid_cents,'due_cents',greatest(0,o.total_cents-o.paid_cents),'refund_due_cents',greatest(0,o.paid_cents-o.total_cents),'payment_method',o.payment_method,'cash_change_for_cents',o.cash_change_for_cents,'card_fee_cents',o.card_fee_cents,'pay_on_delivery',o.pay_on_delivery,'created_at',o.created_at,'updated_at',o.updated_at,'history',(select coalesce(jsonb_agg(jsonb_build_object('status',e.status,'at',e.created_at) order by e.id),'[]') from app_private.online_status_events e where e.order_id=o.id),'changes',changes,'payments',payments);
end $$;

create table app_private.online_status_events (
 id bigint generated always as identity primary key,order_id uuid not null references public.online_orders(id),
 status text not null,created_at timestamptz not null default now()
);
create index online_status_order on app_private.online_status_events(order_id,id);
insert into app_private.online_status_events(order_id,status,created_at) select id,status,updated_at from public.online_orders;
revoke all on app_private.online_status_events from public,anon,authenticated;

create function public.online_collect_delivery_card(p_order uuid,p_key uuid,p_reference text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare o public.online_orders;p public.online_payments;turn uuid;due int;
begin
 if not coalesce(app_private.can_operate(),false) then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 select * into o from public.online_orders where id=p_order for update;
 if not found or o.payment_method<>'card_delivery' or not o.pay_on_delivery or o.status in ('cancelled','awaiting_store','payment_pending') or o.assigned_to is null or (o.assigned_to<>auth.uid() and not app_private.is_admin()) then raise exception 'card_confirmation_not_allowed';end if;
 if p_key is null or length(trim(coalesce(p_reference,''))) not between 8 and 100 then raise exception 'bank_reference_required';end if;
 select * into p from public.online_payments where id=p_key;
 if found then if p.order_id<>o.id or p.method<>'card_delivery' or p.provider_reference<>'terminal:'||trim(p_reference) then raise exception 'idempotency_conflict';end if;return;end if;
 select id into turn from public.shifts where cashier_id=auth.uid() and closed_at is null for update;
 if turn is null then raise exception 'open_shift_required';end if;
 due:=o.total_cents-o.paid_cents;if due<=0 then raise exception 'payment_not_allowed';end if;
 insert into public.online_payments(id,order_id,revision,method,amount_cents,status,provider,provider_reference,confirmed_at,received_by,shift_id)
 values(p_key,o.id,o.revision,'card_delivery',due,'confirmed','card_terminal','terminal:'||trim(p_reference),now(),auth.uid(),turn);
 update public.online_orders set paid_cents=paid_cents+due,paid_at=coalesce(paid_at,now()),updated_at=now() where id=o.id;
 perform app_private.log('online.delivery_card_received','online_order',o.id::text,due);
end $$;

-- Fila de impressão privada. Uma falha ambígua exige conferência humana, evitando
-- repetir automaticamente um cupom que já pode ter saído no papel.
create table app_private.print_bridges (
 id uuid primary key default gen_random_uuid(),name text not null,token_hash text not null unique,
 active boolean not null default true,created_at timestamptz not null default now(),last_seen_at timestamptz
);
create table app_private.online_print_jobs (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references public.online_orders(id),revision int not null,
 payload jsonb not null,status text not null default 'pending' check(status in ('pending','spooling','submitted','uncertain','cancelled')),
 bridge_id uuid references app_private.print_bridges(id),claim_token uuid,lease_until timestamptz,attempts int not null default 0,
 created_at timestamptz not null default now(),submitted_at timestamptz,last_error text,
 unique(order_id,revision)
);
revoke all on app_private.print_bridges,app_private.online_print_jobs from public,anon,authenticated;

create function app_private.online_receipt(p_order uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('number',o.number,'revision',o.revision,'created_at',o.created_at,'fulfillment',o.fulfillment,
 'items',o.items,'subtotal_cents',o.subtotal_cents,'delivery_fee_cents',o.delivery_fee_cents,'card_fee_cents',o.card_fee_cents,
 'total_cents',o.total_cents,'paid_cents',o.paid_cents,'due_cents',greatest(0,o.total_cents-o.paid_cents),
 'payment_method',o.payment_method,'bring_card_terminal',o.payment_method='card_delivery' and o.paid_cents<o.total_cents,'cash_change_for_cents',o.cash_change_for_cents,
 'contact',jsonb_build_object('name',c.name,'phone',c.phone,'address',c.address,'reference',c.reference),
 'change_note',(select reason from public.online_changes where order_id=o.id and status='accepted' order by reviewed_at desc limit 1))
 from public.online_orders o join app_private.online_contacts c on c.order_id=o.id where o.id=p_order
$$;
revoke all on function app_private.online_receipt(uuid) from public,anon,authenticated;

create function app_private.online_order_events() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  insert into app_private.online_status_events(order_id,status) values(new.id,new.status);
 elsif old.status is distinct from new.status then
  insert into app_private.online_status_events(order_id,status) values(new.id,new.status);
  if new.status='preparing' then insert into public.online_notifications(order_id,topic,revision) values(new.id,'order.preparing',new.revision) on conflict do nothing;end if;
 end if;
 if tg_op='UPDATE' then
  if new.paid_cents>=new.total_cents and old.paid_cents<old.total_cents then
   insert into public.online_notifications(order_id,topic,revision) values(new.id,'order.paid',new.revision) on conflict do nothing;
  end if;
  update app_private.online_print_jobs set status='cancelled',last_error='superseded' where order_id=new.id and status='pending' and (revision<new.revision or new.status='cancelled');
 end if;
 if new.status in ('accepted','preparing','ready') then
  insert into app_private.online_print_jobs(order_id,revision,payload) values(new.id,new.revision,app_private.online_receipt(new.id)) on conflict(order_id,revision) do nothing;
 end if;
 return new;
end $$;
revoke all on function app_private.online_order_events() from public,anon,authenticated;
create trigger online_order_events after insert or update on public.online_orders for each row execute function app_private.online_order_events();

create function public.online_register_printer(p_name text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare token text;ident uuid;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if length(trim(coalesce(p_name,''))) not between 2 and 80 then raise exception 'invalid_printer_name';end if;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 update app_private.print_bridges set active=false where active;
 insert into app_private.print_bridges(name,token_hash) values(trim(p_name),encode(extensions.digest(token,'sha256'),'hex')) returning id into ident;
 perform app_private.log('online.printer_registered','print_bridge',ident::text);
 return jsonb_build_object('id',ident,'token',token);
end $$;
create function public.online_revoke_printer(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);update app_private.print_bridges set active=false where id=p_id;
 perform app_private.log('online.printer_revoked','print_bridge',p_id::text);
end $$;
create function app_private.print_bridge(p_token text) returns uuid language plpgsql security definer set search_path='' as $$
declare ident uuid;
begin
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'access_denied' using errcode='42501';end if;
 select id into ident from app_private.print_bridges where active and token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if ident is null then raise exception 'access_denied' using errcode='42501';end if;
 update app_private.print_bridges set last_seen_at=now() where id=ident;return ident;
end $$;
create function public.online_print_claim(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare bridge uuid;j app_private.online_print_jobs;
begin
 bridge:=app_private.print_bridge(p_token);
 update app_private.online_print_jobs set status='uncertain',last_error='agent_disconnected' where status='spooling' and lease_until<now();
 select p.* into j from app_private.online_print_jobs p join public.online_orders o on o.id=p.order_id
 where p.status='pending' and p.revision=o.revision and o.status in ('accepted','preparing','ready','dispatched','completed')
 order by p.created_at,p.id for update of p,o skip locked limit 1;
 if not found then return null;end if;
 update app_private.online_print_jobs set payload=app_private.online_receipt(j.order_id)||jsonb_build_object('reprint',coalesce((j.payload->>'reprint')::boolean,false)),status='spooling',bridge_id=bridge,claim_token=gen_random_uuid(),lease_until=now()+interval '3 minutes',attempts=attempts+1 where id=j.id returning * into j;
 return jsonb_build_object('id',j.id,'claim',j.claim_token,'payload',j.payload);
end $$;
create function public.online_print_finish(p_token text,p_id uuid,p_claim uuid,p_success boolean) returns void language plpgsql security definer set search_path='' as $$
declare bridge uuid;j app_private.online_print_jobs;
begin
 bridge:=app_private.print_bridge(p_token);
 select * into j from app_private.online_print_jobs where id=p_id for update;
 if not found or j.bridge_id<>bridge or j.claim_token is distinct from p_claim then raise exception 'print_claim_mismatch';end if;
 if j.status='submitted' and p_success then return;end if;
 if j.status not in ('spooling','uncertain') then raise exception 'print_claim_expired';end if;
 update app_private.online_print_jobs set status=case when p_success then 'submitted' else 'uncertain' end,submitted_at=case when p_success then now() else null end,lease_until=null,last_error=case when p_success then null else 'check_printer' end where id=j.id;
end $$;
create function public.online_print_monitor() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 return jsonb_build_object('bridges',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active,'last_seen_at',last_seen_at) order by created_at desc),'[]') from app_private.print_bridges),
 'jobs',(select coalesce(jsonb_agg(x),'[]') from (select j.id,o.number,j.revision,case when j.status='spooling' and j.lease_until<now() then 'uncertain' else j.status end status,j.created_at,j.submitted_at,j.last_error from app_private.online_print_jobs j join public.online_orders o on o.id=j.order_id order by j.created_at desc limit 50) x));
end $$;
create function public.online_retry_print(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare j app_private.online_print_jobs;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 select * into j from app_private.online_print_jobs where id=p_id for update;
 if not found or j.status not in ('uncertain','submitted','spooling') or (j.status='spooling' and j.lease_until>now()) then raise exception 'print_not_retryable';end if;
 if not exists(select 1 from public.online_orders where id=j.order_id and revision=j.revision and status<>'cancelled') then raise exception 'print_superseded';end if;
 update app_private.online_print_jobs set status='pending',claim_token=null,bridge_id=null,lease_until=null,submitted_at=null,last_error='manual_reprint',payload=app_private.online_receipt(j.order_id)||jsonb_build_object('reprint',true) where id=j.id;
 perform app_private.log('online.print_retried','print_job',j.id::text);
end $$;
revoke all on function app_private.print_bridge(text) from public,anon,authenticated;
revoke all on function public.online_delivery_quote(jsonb,text,text),public.online_collect_delivery_card(uuid,uuid,text,text),public.online_register_printer(text,text),public.online_revoke_printer(uuid,text),public.online_print_claim(text),public.online_print_finish(text,uuid,uuid,boolean),public.online_print_monitor(),public.online_retry_print(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.online_delivery_quote(jsonb,text,text),public.online_print_claim(text),public.online_print_finish(text,uuid,uuid,boolean) to service_role;
grant execute on function public.online_collect_delivery_card(uuid,uuid,text,text),public.online_register_printer(text,text),public.online_revoke_printer(uuid,text),public.online_print_monitor(),public.online_retry_print(uuid,text) to authenticated;
alter table app_private.online_tracking_links enable row level security;
alter table app_private.online_status_events enable row level security;
alter table app_private.print_bridges enable row level security;
alter table app_private.online_print_jobs enable row level security;
notify pgrst, 'reload schema';
commit;
