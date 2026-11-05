begin;
create schema if not exists app_private;
revoke all on schema app_private from public;
create extension if not exists pgcrypto with schema extensions;

create type public.app_role as enum ('admin','cashier','kitchen');
create type public.sector as enum ('grill','fryer','bar');
create type public.order_state as enum ('pending_payment','queued','preparing','ready','completed','cancelled');
create type public.payment_method as enum ('cash','pix','tef');
create type public.payment_state as enum ('pending','confirmed','failed','refunded');

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null check (length(name) between 2 and 100),
 role public.app_role not null default 'cashier',
 sector public.sector,
 active boolean not null default false,
 check (role <> 'kitchen' or sector is not null)
);
create function app_private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,name) values(new.id,coalesce(nullif(left(new.raw_user_meta_data->>'name',100),''),'Novo funcionário'));
 return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function app_private.new_user();

create function app_private.role() returns public.app_role language sql stable security definer set search_path='' as $$
 select p.role from public.profiles p where p.id=auth.uid() and p.active
$$;
create function app_private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(app_private.role()='admin',false)
$$;
create table app_private.pin_credentials (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 pin_hash text not null,
 failures int not null default 0,
 locked_until timestamptz
);
create table app_private.terminal_leases (
 user_id uuid not null references public.profiles(id) on delete cascade,
 session_id text not null,
 expires_at timestamptz not null,
 primary key(user_id,session_id)
);
create function app_private.can_operate() returns boolean language sql stable security definer set search_path='' as $$
 select app_private.is_admin() or (app_private.role()='cashier' and exists(
 select 1 from app_private.terminal_leases l where l.user_id=auth.uid() and l.session_id=auth.jwt()->>'session_id' and l.expires_at>now()))
$$;
create function public.set_staff_pin(p_user uuid,p_pin text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 if p_pin is null or p_pin !~ '^[0-9]{4}$' or not exists(select 1 from public.profiles where id=p_user and role='cashier' and active) then raise exception 'invalid_staff_pin'; end if;
 insert into app_private.pin_credentials(user_id,pin_hash) values(p_user,extensions.crypt(p_pin,extensions.gen_salt('bf',10)))
 on conflict(user_id) do update set pin_hash=excluded.pin_hash,failures=0,locked_until=null;
 delete from app_private.terminal_leases where user_id=p_user;
end $$;
create function public.unlock_terminal(p_pin text) returns jsonb language plpgsql security definer set search_path='' as $$
declare credential app_private.pin_credentials; expiry timestamptz; sid text:=auth.jwt()->>'session_id';
begin
 if app_private.role()<>'cashier' or app_private.role() is null or sid is null then raise exception 'access_denied' using errcode='42501'; end if;
 select * into credential from app_private.pin_credentials where user_id=auth.uid() for update;
 if not found then return jsonb_build_object('ok',false,'error','PIN ainda não configurado pelo administrador.'); end if;
 if credential.locked_until>now() then return jsonb_build_object('ok',false,'error','Muitas tentativas. Aguarde cinco minutos.'); end if;
 if p_pin is null or p_pin !~ '^[0-9]{4}$' or extensions.crypt(p_pin,credential.pin_hash)<>credential.pin_hash then
  update app_private.pin_credentials set failures=case when failures>=4 then 0 else failures+1 end, locked_until=case when failures>=4 then now()+interval '5 minutes' else null end where user_id=auth.uid();
  return jsonb_build_object('ok',false,'error','PIN incorreto.');
 end if;
 expiry:=now()+interval '15 minutes';
 update app_private.pin_credentials set failures=0,locked_until=null where user_id=auth.uid();
 insert into app_private.terminal_leases values(auth.uid(),sid,expiry) on conflict(user_id,session_id) do update set expires_at=excluded.expires_at;
 return jsonb_build_object('ok',true,'expires_at',expiry);
end $$;
create function public.lock_terminal() returns void language sql security definer set search_path='' as $$
 delete from app_private.terminal_leases where user_id=auth.uid() and session_id=auth.jwt()->>'session_id'
$$;

create table public.products (
 id text primary key,
 name text not null,
 category text not null,
 description text not null default '',
 price_cents int not null check(price_cents>0 and price_cents<=10000000),
 sector public.sector not null,
 image_path text not null,
 allowed_modifiers text[] not null default '{}',
 active boolean not null default true
);
create table public.ingredients (
 id uuid primary key default gen_random_uuid(), name text not null, unit text not null check(unit in ('un','g','ml')),
 stock numeric(14,3) not null default 0, minimum_stock numeric(14,3) not null default 0 check(minimum_stock>=0),
 unit_cost_cents numeric(12,4) not null default 0 check(unit_cost_cents>=0)
);
create table public.recipe_items (
 product_id text not null references public.products(id), ingredient_id uuid not null references public.ingredients(id),
 quantity numeric(12,3) not null check(quantity>0),primary key(product_id,ingredient_id)
);
create table public.shifts (
 id uuid primary key default gen_random_uuid(), cashier_id uuid not null references public.profiles(id),
 opened_at timestamptz not null default now(), closed_at timestamptz,
 opening_cents int not null check(opening_cents>=0), closing_counted_cents int check(closing_counted_cents>=0),
 check((closed_at is null)=(closing_counted_cents is null))
);
create unique index one_open_shift on public.shifts(cashier_id) where closed_at is null;
create table public.orders (
 id uuid primary key default gen_random_uuid(), number bigint generated always as identity unique,
 cashier_id uuid references public.profiles(id), shift_id uuid references public.shifts(id),
 source text not null default 'pos' check(source in ('pos','self_service','whatsapp_bot')),
 check((source='pos' and cashier_id is not null and shift_id is not null) or (source<>'pos' and cashier_id is null and shift_id is null)),
 idempotency_key uuid not null unique, request_body jsonb not null,
 customer text not null check(length(customer) between 1 and 100), channel text not null check(channel in ('counter','whatsapp','table','delivery')),
 status public.order_state not null default 'pending_payment', total_cents int not null check(total_cents>0),
 created_at timestamptz not null default now(), paid_at timestamptz, completed_at timestamptz
);
create table public.order_items (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id),
 product_id text not null references public.products(id), name text not null,
 quantity int not null check(quantity between 1 and 100), unit_price_cents int not null check(unit_price_cents>0),
 sector public.sector not null, modifiers text[] not null default '{}', notes text not null default '' check(length(notes)<=500)
);
create table public.payment_attempts (
 id uuid primary key, order_id uuid not null references public.orders(id),
 method public.payment_method not null, status public.payment_state not null default 'pending',
 amount_cents int not null check(amount_cents>0),provider_reference text unique,
 created_at timestamptz not null default now(), confirmed_at timestamptz
);
create unique index one_pending_payment on public.payment_attempts(order_id) where status='pending';
create unique index one_confirmed_payment on public.payment_attempts(order_id) where status='confirmed';
create table public.kitchen_tickets (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id),
 order_number bigint not null, customer text not null, sector public.sector not null,
 items jsonb not null, status text not null default 'queued' check(status in ('queued','preparing','ready')),
 created_at timestamptz not null default now(), started_at timestamptz, ready_at timestamptz,
 unique(order_id,sector)
);
create table public.stock_movements (
 id bigint generated always as identity primary key, order_id uuid not null references public.orders(id),
 ingredient_id uuid not null references public.ingredients(id),quantity numeric(14,3) not null,
 created_at timestamptz not null default now(),unique(order_id,ingredient_id)
);
create table public.audit_log (
 id bigint generated always as identity primary key, actor_id uuid references public.profiles(id),
 action text not null, entity_id uuid, created_at timestamptz not null default now()
);
create table app_private.webhook_events (
 provider text not null,event_id text not null,payload_hash text not null,attempt_id uuid not null references public.payment_attempts(id),processed_at timestamptz not null default now(),primary key(provider,event_id)
);
create table public.integration_outbox (
 id uuid primary key default gen_random_uuid(), topic text not null,order_id uuid not null references public.orders(id),
 payload jsonb not null default '{}',attempts int not null default 0,next_attempt_at timestamptz not null default now(),delivered_at timestamptz,
 unique(topic,order_id)
);
create index orders_cashier_time on public.orders(cashier_id,created_at desc);
create index tickets_sector_status on public.kitchen_tickets(sector,status,created_at);
create index order_items_order on public.order_items(order_id);

create function public.open_shift(p_opening_cents int) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; existing public.shifts;
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1));
 select * into existing from public.shifts where cashier_id=auth.uid() and closed_at is null;
 if found then
  if existing.opening_cents<>p_opening_cents then raise exception 'shift_already_open'; end if;
  return existing.id;
 end if;
 insert into public.shifts(cashier_id,opening_cents) values(auth.uid(),p_opening_cents) returning id into result;
 return result;
end $$;
create function public.close_shift(p_shift uuid,p_counted_cents int) returns void language plpgsql security definer set search_path='' as $$
declare existing public.shifts;
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501'; end if;
 select * into existing from public.shifts where id=p_shift and cashier_id=auth.uid() for update;
 if not found then raise exception 'shift_unavailable'; end if;
 if existing.closed_at is not null then
  if existing.closing_counted_cents=p_counted_cents then return; end if;
  raise exception 'closing_count_conflict';
 end if;
 if exists(select 1 from public.orders where shift_id=p_shift and status='pending_payment') then raise exception 'pending_orders_in_shift'; end if;
 update public.shifts set closed_at=now(),closing_counted_cents=p_counted_cents where id=p_shift;
end $$;
create function public.create_order(p_key uuid,p_customer text,p_channel text,p_items jsonb) returns public.orders language plpgsql security definer set search_path='' as $$
declare result public.orders; item jsonb; product public.products; shift uuid; qty int; mods text[]; total bigint:=0;
 req jsonb:=jsonb_build_object('customer',p_customer,'channel',p_channel,'items',p_items);
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501'; end if;
 if p_key is null then raise exception 'missing_idempotency_key'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 select * into result from public.orders where idempotency_key=p_key;
 if found then
  if result.cashier_id<>auth.uid() or result.request_body<>req then raise exception 'idempotency_conflict'; end if;
  return result;
 end if;
 select id into shift from public.shifts where cashier_id=auth.uid() and closed_at is null for update;
 if shift is null then raise exception 'open_shift_required'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'invalid_items'; end if;
 -- Lock the selected products so pricing cannot change halfway through this transaction.
 perform 1 from public.products where id in(select x->>'product_id' from jsonb_array_elements(p_items) x) order by id for share;
 for item in select * from jsonb_array_elements(p_items) loop
  select * into product from public.products where id=item->>'product_id' and active;
  if not found then raise exception 'product_unavailable'; end if;
  if item->>'quantity' !~ '^[0-9]+$' then raise exception 'invalid_quantity'; end if;
  qty:=(item->>'quantity')::int;
  if qty not between 1 and 100 then raise exception 'invalid_quantity'; end if;
  select coalesce(array_agg(value),'{}') into mods from jsonb_array_elements_text(coalesce(item->'modifiers','[]'));
  if not mods <@ product.allowed_modifiers then raise exception 'invalid_modifier'; end if;
  if (select count(*) from unnest(mods) v where v like 'Ponto:%')>1 then raise exception 'conflicting_modifiers'; end if;
  total:=total+product.price_cents::bigint*qty;
 end loop;
 if total>2147483647 then raise exception 'order_too_large'; end if;
 insert into public.orders(cashier_id,shift_id,idempotency_key,request_body,customer,channel,total_cents)
 values(auth.uid(),shift,p_key,req,trim(p_customer),p_channel,total) returning * into result;
 for item in select * from jsonb_array_elements(p_items) loop
  select * into product from public.products where id=item->>'product_id';
  insert into public.order_items(order_id,product_id,name,quantity,unit_price_cents,sector,modifiers,notes)
  values(result.id,product.id,product.name,(item->>'quantity')::int,product.price_cents,product.sector,
   array(select jsonb_array_elements_text(coalesce(item->'modifiers','[]'))),coalesce(item->>'notes',''));
 end loop;
 return result;
end $$;
create function public.begin_payment(p_order uuid,p_method public.payment_method,p_key uuid) returns public.payment_attempts language plpgsql security definer set search_path='' as $$
declare ord public.orders; attempt public.payment_attempts;
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501'; end if;
 select * into ord from public.orders where id=p_order and (cashier_id=auth.uid() or app_private.is_admin()) for update;
 if not found then raise exception 'order_unavailable'; end if;
 select * into attempt from public.payment_attempts where id=p_key;
 if found then
  if attempt.order_id<>p_order or attempt.method<>p_method then raise exception 'idempotency_conflict'; end if;
  return attempt;
 end if;
 if ord.status<>'pending_payment' then raise exception 'payment_not_allowed'; end if;
 insert into public.payment_attempts(id,order_id,method,amount_cents) values(p_key,p_order,p_method,ord.total_cents) returning * into attempt;
 return attempt;
end $$;
create function app_private.release_order(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare ord public.orders; consumption record;
begin
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
create function public.confirm_cash(p_attempt uuid) returns void language plpgsql security definer set search_path='' as $$
declare attempt public.payment_attempts;
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501'; end if;
 select * into attempt from public.payment_attempts where id=p_attempt for update;
 if not found or attempt.method<>'cash' or attempt.status not in ('pending','confirmed') or not exists(select 1 from public.orders where id=attempt.order_id and (cashier_id=auth.uid() or app_private.is_admin())) then raise exception 'cash_confirmation_not_allowed'; end if;
 update public.payment_attempts set status='confirmed',confirmed_at=coalesce(confirmed_at,now()) where id=p_attempt;
 perform app_private.release_order(attempt.order_id);
end $$;
-- Only the trusted, signature-verifying payment adapter may invoke this RPC.
create function public.confirm_provider_payment(p_attempt uuid,p_amount int,p_reference text,p_provider text,p_event text,p_payload_hash text) returns void language plpgsql security definer set search_path='' as $$
declare attempt public.payment_attempts; previous_hash text; previous_attempt uuid;
begin
 select * into attempt from public.payment_attempts where id=p_attempt for update;
 if not found or p_amount is null or coalesce(p_reference,'')='' or coalesce(p_provider,'')='' or coalesce(p_event,'')='' or coalesce(p_payload_hash,'')='' or attempt.method='cash' or attempt.amount_cents<>p_amount or attempt.status not in ('pending','confirmed') then raise exception 'invalid_provider_payment'; end if;
 select payload_hash,attempt_id into previous_hash,previous_attempt from app_private.webhook_events where provider=p_provider and event_id=p_event;
 if found then
  if previous_hash<>p_payload_hash or previous_attempt<>p_attempt then raise exception 'event_conflict'; end if;
  return;
 end if;
 if attempt.provider_reference is not null and attempt.provider_reference<>p_reference then raise exception 'reference_conflict'; end if;
 insert into app_private.webhook_events values(p_provider,p_event,p_payload_hash,p_attempt,now());
 update public.payment_attempts set status='confirmed',provider_reference=p_reference,confirmed_at=coalesce(confirmed_at,now()) where id=p_attempt;
 perform app_private.release_order(attempt.order_id);
end $$;
create function public.update_ticket(p_ticket uuid,p_status text) returns void language plpgsql security definer set search_path='' as $$
declare ticket public.kitchen_tickets;
begin
 if app_private.role() not in ('admin','kitchen') or app_private.role() is null then raise exception 'access_denied' using errcode='42501'; end if;
 select * into ticket from public.kitchen_tickets where id=p_ticket for update;
 if not found or (not app_private.is_admin() and ticket.sector<>(select sector from public.profiles where id=auth.uid())) then raise exception 'access_denied' using errcode='42501'; end if;
 if ticket.status=p_status then return; end if;
 if not ((ticket.status='queued' and p_status='preparing') or (ticket.status='preparing' and p_status='ready')) then raise exception 'invalid_transition'; end if;
 perform 1 from public.orders where id=ticket.order_id for update;
 update public.kitchen_tickets set status=p_status,started_at=case when p_status='preparing' then now() else started_at end,ready_at=case when p_status='ready' then now() else ready_at end where id=p_ticket;
 update public.orders set status=case when not exists(select 1 from public.kitchen_tickets where order_id=ticket.order_id and status<>'ready') then 'ready'::public.order_state else 'preparing'::public.order_state end where id=ticket.order_id;
 insert into public.integration_outbox(topic,order_id) select 'order.ready',ticket.order_id where not exists(select 1 from public.kitchen_tickets where order_id=ticket.order_id and status<>'ready') on conflict do nothing;
end $$;
create function public.complete_order(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501'; end if;
 update public.orders set status='completed',completed_at=coalesce(completed_at,now()) where id=p_order and status in ('ready','completed') and (cashier_id=auth.uid() or app_private.is_admin());
 if not found then raise exception 'order_not_ready'; end if;
end $$;
create function public.cancel_unpaid_order(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.can_operate() then raise exception 'access_denied' using errcode='42501'; end if;
 perform 1 from public.orders where id=p_order and status='pending_payment' and (cashier_id=auth.uid() or app_private.is_admin()) for update;
 if not found or exists(select 1 from public.payment_attempts where order_id=p_order and status in ('pending','confirmed')) then raise exception 'payment_reconciliation_required'; end if;
 update public.orders set status='cancelled' where id=p_order;
 insert into public.audit_log(actor_id,action,entity_id) values(auth.uid(),'cancel_unpaid',p_order);
end $$;

create function public.manage_staff(p_user uuid,p_role public.app_role,p_sector public.sector,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 perform 1 from public.profiles order by id for update;
 if not exists(select 1 from public.profiles where id=p_user) then raise exception 'user_not_found'; end if;
 if exists(select 1 from public.profiles where id=p_user and active and role='admin')
 and (p_role<>'admin' or not p_active) and not exists(select 1 from public.profiles where active and role='admin' and id<>p_user) then raise exception 'last_admin'; end if;
 update public.profiles set role=p_role,sector=p_sector,active=p_active where id=p_user;
 delete from app_private.terminal_leases where user_id=p_user;
 insert into public.audit_log(actor_id,action,entity_id) values(auth.uid(),'manage_staff',p_user);
end $$;

-- Future migrations must explicitly grant access rather than inherit broad
-- Supabase table/function defaults from the migration owner.
alter default privileges in schema public revoke all on tables from anon,authenticated;
alter default privileges in schema public revoke execute on functions from public,anon,authenticated;
alter default privileges in schema app_private revoke execute on functions from public,anon,authenticated;

-- RLS is enforced even for direct REST calls. No browser gets service_role.
alter table public.profiles enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or app_private.is_admin());
alter table public.products enable row level security;
create policy product_read on public.products for select to authenticated using(app_private.role() in ('admin','cashier') and (active or app_private.is_admin()));
create policy product_admin on public.products for all to authenticated using(app_private.is_admin()) with check(app_private.is_admin());
alter table public.ingredients enable row level security;
create policy ingredients_admin on public.ingredients for all to authenticated using(app_private.is_admin()) with check(app_private.is_admin());
alter table public.recipe_items enable row level security;
create policy recipes_admin on public.recipe_items for all to authenticated using(app_private.is_admin()) with check(app_private.is_admin());
alter table public.shifts enable row level security;
create policy shifts_read on public.shifts for select to authenticated using(app_private.is_admin() or (app_private.can_operate() and cashier_id=auth.uid()));
alter table public.orders enable row level security;
create policy orders_read on public.orders for select to authenticated using(app_private.is_admin() or (app_private.can_operate() and cashier_id=auth.uid()));
alter table public.order_items enable row level security;
create policy items_read on public.order_items for select to authenticated using(exists(select 1 from public.orders where id=order_id));
alter table public.payment_attempts enable row level security;
create policy payments_read on public.payment_attempts for select to authenticated using(exists(select 1 from public.orders where id=order_id));
alter table public.kitchen_tickets enable row level security;
create policy ticket_read on public.kitchen_tickets for select to authenticated using(app_private.is_admin() or (app_private.role()='kitchen' and sector=(select p.sector from public.profiles p where p.id=auth.uid())));
alter table public.stock_movements enable row level security;
create policy stock_admin on public.stock_movements for select to authenticated using(app_private.is_admin());
alter table public.audit_log enable row level security;
create policy audit_admin on public.audit_log for select to authenticated using(app_private.is_admin());
alter table public.integration_outbox enable row level security;
create policy outbox_admin on public.integration_outbox for select to authenticated using(app_private.is_admin());

revoke all on all tables in schema public from anon,authenticated;
grant select on public.profiles,public.products,public.ingredients,public.recipe_items,public.shifts,public.orders,public.order_items,public.payment_attempts,public.kitchen_tickets,public.stock_movements,public.audit_log,public.integration_outbox to authenticated;
grant insert,update,delete on public.products,public.ingredients,public.recipe_items to authenticated;
grant usage on schema app_private to authenticated;
revoke all on all functions in schema public from public,anon,authenticated;
revoke all on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.role(),app_private.is_admin(),app_private.can_operate() to authenticated;
grant execute on function public.set_staff_pin(uuid,text),public.unlock_terminal(text),public.lock_terminal(),public.open_shift(int),public.close_shift(uuid,int),public.create_order(uuid,text,text,jsonb),public.begin_payment(uuid,public.payment_method,uuid),public.confirm_cash(uuid),public.update_ticket(uuid,text),public.complete_order(uuid),public.cancel_unpaid_order(uuid),public.manage_staff(uuid,public.app_role,public.sector,boolean) to authenticated;
grant execute on function public.confirm_provider_payment(uuid,int,text,text,text,text) to service_role;
grant all on all tables in schema public to service_role;
grant usage,select on all sequences in schema public to service_role;

-- Only sanitized kitchen tickets are published: no financial rows in Realtime.
alter publication supabase_realtime add table public.kitchen_tickets;
commit;
