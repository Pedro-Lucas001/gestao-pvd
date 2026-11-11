-- GERADO por npm run activation:prepare. Não editar manualmente.
-- SOMENTE PARA UM PROJETO SUPABASE NOVO E VAZIO.
-- Contrato em inglês do frontend; NÃO misturar com supabase/sql_editor/.
-- Inclui todas as migrações e seed em uma única transação.
-- NÃO inclui fixtures de testes nem promove usuários a administrador.
begin;
do $activation_guard$
begin
  if exists (
    select 1 from information_schema.tables where table_schema = 'public'
  ) or exists (
    select 1 from pg_namespace where nspname = 'app_private'
  ) or exists (
    select 1 from auth.users
  ) or exists (
    select 1 from storage.buckets
  ) then
    raise exception 'ACTIVATION_REQUIRES_EMPTY_PROJECT: já existem tabelas, usuários, buckets ou estrutura operacional. Use as migrações incrementais após revisar o banco.';
  end if;
end
$activation_guard$;

-- SOURCE: supabase/migrations/202611050001_core.sql
-- SHA256: f6188b7c61eded799f731c18deb38dc314bb4d6499738499b8aa1259a04c3c60
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

-- SOURCE: supabase/migrations/202611050002_security.sql
-- SHA256: 07b99604a6064fff369cd1afe87056d7542db512fd675a6a57a8e034bfd2b9a5
-- An append-only audit stream. Store amounts/reasons, never full customer rows,
-- PINs, tokens, passwords, card data or delivery addresses in audit payloads.
alter table public.audit_log add column amount_cents bigint not null default 0;
alter table public.audit_log add column justification text not null default 'Registro operacional anterior à auditoria avançada';
alter table public.audit_log add column quantity_delta numeric(14,3);
alter table public.audit_log add column entity_type text;
alter table public.audit_log add column entity_key text;
alter table public.audit_log add column actor_kind text not null default 'user' check(actor_kind in ('user','integration','system'));
create function app_private.immutable_log() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'immutable_audit_log' using errcode='42501'; end $$;
create trigger audit_no_changes before update or delete on public.audit_log for each row execute function app_private.immutable_log();
create trigger audit_no_truncate before truncate on public.audit_log for each statement execute function app_private.immutable_log();
revoke all on public.audit_log from anon,authenticated,service_role;
grant select on public.audit_log to authenticated;
create function app_private.reason(p_reason text) returns void language plpgsql set search_path='' as $$
begin
 if p_reason is null or length(trim(p_reason)) not between 5 and 500 then raise exception 'justification_required'; end if;
 perform set_config('app.audit_reason',trim(p_reason),true);
end $$;
create function app_private.log(p_action text,p_type text,p_key text,p_amount bigint default 0) returns void language plpgsql security definer set search_path='' as $$
declare reason text:=nullif(current_setting('app.audit_reason',true),''); actor uuid:=auth.uid();
begin
 if reason is null then raise exception 'justification_required'; end if;
 insert into public.audit_log(actor_id,action,entity_type,entity_key,amount_cents,justification,actor_kind)
 values(actor,p_action,p_type,p_key,p_amount,reason,case when actor is not null then 'user' when auth.jwt()->>'role'='service_role' then 'integration' else 'system' end);
end $$;
create function app_private.audit_insert_defaults() returns trigger language plpgsql set search_path='' as $$
begin
 if new.action='inventory.changed' then new.quantity_delta:=nullif(current_setting('app.audit_quantity',true),'')::numeric;end if;
 new.justification:=coalesce(nullif(current_setting('app.audit_reason',true),''),new.justification);
 if new.actor_id is null then new.actor_kind:=case when auth.jwt()->>'role'='service_role' then 'integration' else 'system' end; end if;
 return new;
end $$;
create trigger audit_insert_defaults before insert on public.audit_log for each row execute function app_private.audit_insert_defaults();

-- Registered device identity prevents bypassing a terminal lockout by submitting
-- random terminal IDs or switching staff accounts. Device tokens are never PINs.
create table public.terminals(id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 2 and 100),active boolean not null default true,created_at timestamptz not null default now());
create table app_private.terminal_secrets(terminal_id uuid primary key references public.terminals(id),token_hash text not null unique);
create table app_private.terminal_attempts(terminal_id uuid primary key references public.terminals(id),failures int not null default 0 check(failures between 0 and 4),locked_until timestamptz);
alter table public.terminals enable row level security;
create policy terminals_admin on public.terminals for select to authenticated using(app_private.is_admin());
grant select on public.terminals to authenticated;
delete from app_private.terminal_leases;
alter table app_private.terminal_leases add column terminal_id uuid not null references public.terminals(id);
create function public.register_terminal(p_name text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare device uuid; token text:=encode(extensions.gen_random_bytes(32),'hex');
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 perform app_private.reason(p_reason);
 insert into public.terminals(name) values(trim(p_name)) returning id into device;
 insert into app_private.terminal_secrets values(device,encode(extensions.digest(token,'sha256'),'hex'));
 insert into app_private.terminal_attempts(terminal_id) values(device);
 perform app_private.log('terminal.registered','terminal',device::text);
 return jsonb_build_object('id',device,'token',token);
end $$;
create function public.revoke_terminal(p_terminal uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 perform app_private.reason(p_reason);
 update public.terminals set active=false where id=p_terminal;
 delete from app_private.terminal_leases where terminal_id=p_terminal;
 perform app_private.log('terminal.revoked','terminal',p_terminal::text);
end $$;
create or replace function public.set_staff_pin(p_user uuid,p_pin text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 if p_pin is null or p_pin !~ '^[0-9]{4}$' or not exists(select 1 from public.profiles where id=p_user and active) then raise exception 'invalid_staff_pin'; end if;
 insert into app_private.pin_credentials(user_id,pin_hash) values(p_user,extensions.crypt(p_pin,extensions.gen_salt('bf',10)))
 on conflict(user_id) do update set pin_hash=excluded.pin_hash,failures=0,locked_until=null;
 delete from app_private.terminal_leases where user_id=p_user;
 perform app_private.reason('Definição ou troca de PIN de terminal');
 perform app_private.log('staff.pin_changed','profile',p_user::text);
end $$;
revoke execute on function public.unlock_terminal(text) from authenticated;
create function public.unlock_terminal(p_pin text,p_terminal_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare credential app_private.pin_credentials; device uuid; attempts app_private.terminal_attempts;
 sid text:=auth.jwt()->>'session_id'; expiry timestamptz:=now()+interval '10 minutes';
begin
 if app_private.role() is null or sid is null then raise exception 'access_denied' using errcode='42501'; end if;
 select s.terminal_id into device from app_private.terminal_secrets s join public.terminals d on d.id=s.terminal_id
 where s.token_hash=encode(extensions.digest(p_terminal_token,'sha256'),'hex') and d.active;
 if device is null then return jsonb_build_object('ok',false,'error','Terminal não cadastrado ou revogado. Solicite o cadastro ao administrador.'); end if;
 select * into attempts from app_private.terminal_attempts where terminal_id=device for update;
 if attempts.locked_until>now() then return jsonb_build_object('ok',false,'retry_at',attempts.locked_until,'error','Terminal bloqueado por 3 minutos após cinco erros consecutivos.'); end if;
 select * into credential from app_private.pin_credentials where user_id=auth.uid() for update;
 if not found then return jsonb_build_object('ok',false,'error','Seu PIN ainda não foi configurado pelo administrador.'); end if;
 if credential.locked_until>now() then return jsonb_build_object('ok',false,'retry_at',credential.locked_until,'error','Conta temporariamente bloqueada por 3 minutos.'); end if;
 if p_pin is null or p_pin !~ '^[0-9]{4}$' or extensions.crypt(p_pin,credential.pin_hash)<>credential.pin_hash then
  update app_private.terminal_attempts set failures=case when failures=4 then 0 else failures+1 end,
   locked_until=case when failures=4 then now()+interval '3 minutes' else null end where terminal_id=device returning * into attempts;
  update app_private.pin_credentials set failures=case when failures>=4 then 0 else failures+1 end,
   locked_until=case when failures>=4 then now()+interval '3 minutes' else null end where user_id=auth.uid();
  if attempts.locked_until is not null then
   perform app_private.reason('Cinco tentativas incorretas consecutivas no terminal');
   perform app_private.log('terminal.pin_lockout','terminal',device::text);
  end if;
  return jsonb_build_object('ok',false,'retry_at',attempts.locked_until,'error',case when attempts.locked_until is null then 'PIN incorreto.' else 'Terminal bloqueado por 3 minutos após cinco erros consecutivos.' end);
 end if;
 update app_private.terminal_attempts set failures=0,locked_until=null where terminal_id=device;
 update app_private.pin_credentials set failures=0,locked_until=null where user_id=auth.uid();
 insert into app_private.terminal_leases(user_id,session_id,expires_at,terminal_id) values(auth.uid(),sid,expiry,device)
 on conflict(user_id,session_id) do update set expires_at=excluded.expires_at,terminal_id=excluded.terminal_id;
 return jsonb_build_object('ok',true,'expires_at',expiry);
end $$;
create function app_private.terminal_open() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from app_private.terminal_leases l join public.terminals d on d.id=l.terminal_id where l.user_id=auth.uid() and l.session_id=auth.jwt()->>'session_id' and l.expires_at>now() and d.active)
$$;
create or replace function app_private.can_operate() returns boolean language sql stable security definer set search_path='' as $$
 select app_private.is_admin() or (app_private.role()='cashier' and app_private.terminal_open())
$$;
create function public.heartbeat_terminal() returns jsonb language plpgsql security definer set search_path='' as $$
declare expiry timestamptz;
begin
 if app_private.role() is null or not app_private.terminal_open() then return jsonb_build_object('ok',false); end if;
 update app_private.terminal_leases set expires_at=now()+interval '10 minutes' where user_id=auth.uid() and session_id=auth.jwt()->>'session_id' returning expires_at into expiry;
 return jsonb_build_object('ok',true,'expires_at',expiry);
end $$;
-- No name/phone/address in kitchen tickets. Use only the operational order alias.
update public.kitchen_tickets set customer='Pedido #'||order_number;
create function app_private.sanitize_ticket() returns trigger language plpgsql set search_path='' as $$
begin new.customer:='Pedido #'||new.order_number; return new; end $$;
create trigger sanitize_ticket before insert or update on public.kitchen_tickets for each row execute function app_private.sanitize_ticket();
drop policy ticket_read on public.kitchen_tickets;
create policy ticket_read on public.kitchen_tickets for select to authenticated using(app_private.is_admin() or (app_private.role()='kitchen' and app_private.terminal_open() and sector=(select p.sector from public.profiles p where p.id=auth.uid())));
-- Direct REST edits must not bypass validation, reasons and automatic audit.
revoke insert,update,delete on public.products,public.ingredients,public.recipe_items from authenticated;
-- Revoke broad service table writes. Integrations use narrowly scoped RPCs.
revoke insert,update,delete,truncate on all tables in schema public from service_role;
revoke all on public.audit_log from service_role;

revoke all on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.role(),app_private.is_admin(),app_private.can_operate(),app_private.terminal_open() to authenticated;
grant execute on function public.register_terminal(text,text),public.revoke_terminal(uuid,text),public.unlock_terminal(text,text),public.heartbeat_terminal() to authenticated;
create or replace function public.update_ticket(p_ticket uuid,p_status text) returns void language plpgsql security definer set search_path='' as $$
declare ticket public.kitchen_tickets;
begin
 if (not app_private.is_admin() and not app_private.terminal_open()) or app_private.role() not in ('admin','kitchen') or app_private.role() is null then raise exception 'access_denied' using errcode='42501'; end if;
 select * into ticket from public.kitchen_tickets where id=p_ticket for update;
 if not found or (not app_private.is_admin() and ticket.sector<>(select sector from public.profiles where id=auth.uid())) then raise exception 'access_denied' using errcode='42501'; end if;
 if ticket.status=p_status then return; end if;
 if not ((ticket.status='queued' and p_status='preparing') or (ticket.status='preparing' and p_status='ready')) then raise exception 'invalid_transition'; end if;
 perform 1 from public.orders where id=ticket.order_id for update;
 update public.kitchen_tickets set status=p_status,started_at=case when p_status='preparing' then now() else started_at end,ready_at=case when p_status='ready' then now() else ready_at end where id=p_ticket;
 update public.orders set status=case when not exists(select 1 from public.kitchen_tickets where order_id=ticket.order_id and status<>'ready') then 'ready'::public.order_state else 'preparing'::public.order_state end where id=ticket.order_id;
 insert into public.integration_outbox(topic,order_id) select 'order.ready',ticket.order_id where not exists(select 1 from public.kitchen_tickets where order_id=ticket.order_id and status<>'ready') on conflict do nothing;
end $$;

-- SOURCE: supabase/migrations/202611050003_management.sql
-- SHA256: 267b7894be067921c7c42e35df16110be3bd83120a5396e664ce2d36ca74dbb9
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

-- SOURCE: supabase/migrations/202611050004_commerce.sql
-- SHA256: fc7ad5e1de498bce42d5fc9e51ec18be83ccf77e0822990946bf507deb1381d1
create table public.order_links(id uuid primary key default gen_random_uuid(),label text not null check(length(label) between 2 and 80),channel text not null check(channel in ('table','delivery')),active boolean not null default true,expires_at timestamptz not null,created_at timestamptz not null default now());
create table app_private.order_link_secrets(link_id uuid primary key references public.order_links(id),token_hash text not null unique,window_started timestamptz not null default now(),submissions int not null default 0);
create table app_private.order_tracking(order_id uuid primary key references public.orders(id),token_hash text not null unique,link_id uuid not null references public.order_links(id));
create table app_private.payment_artifacts(attempt_id uuid primary key references public.payment_attempts(id),copy_paste text not null,expires_at timestamptz);
create function public.create_order_link(p_label text,p_channel text,p_days int,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare link uuid; token text:=encode(extensions.gen_random_bytes(32),'hex');
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if p_days is null or p_days not between 1 and 90 then raise exception 'invalid_link_expiry';end if;
 insert into public.order_links(label,channel,expires_at) values(trim(p_label),p_channel,now()+make_interval(days=>p_days)) returning id into link;
 insert into app_private.order_link_secrets(link_id,token_hash) values(link,encode(extensions.digest(token,'sha256'),'hex'));
 perform app_private.log('checkout.link_created','order_link',link::text);
 return jsonb_build_object('id',link,'token',token);
end $$;
create function public.revoke_order_link(p_link uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);update public.order_links set active=false where id=p_link;
 perform app_private.log('checkout.link_revoked','order_link',p_link::text);
end $$;
create function app_private.order_link(p_token text) returns public.order_links language plpgsql security definer set search_path='' as $$
declare link public.order_links;
begin
 select l.* into link from public.order_links l join app_private.order_link_secrets s on s.link_id=l.id
 where s.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and l.active and l.expires_at>now();
 if not found then raise exception 'link_unavailable' using errcode='42501';end if;return link;
end $$;
create function public.checkout_menu(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare link public.order_links; catalog jsonb;
begin
 link:=app_private.order_link(p_token);
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category',p.category,'description',p.description,'price_cents',p.price_cents,'image_path',p.image_path,'allowed_modifiers',p.allowed_modifiers) order by p.category,p.price_cents),'[]') into catalog from public.products p where active;
 return jsonb_build_object('label',link.label,'channel',link.channel,'products',catalog);
end $$;
create function public.checkout_order(p_token text,p_key uuid,p_tracking text,p_contact jsonb,p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare link public.order_links; result public.orders; item jsonb; product public.products; qty int; mods text[];total bigint:=0;limiter app_private.order_link_secrets;
 request_hash text:=encode(extensions.digest(jsonb_build_object('contact',p_contact,'items',p_items)::text,'sha256'),'hex'); previous_hash text;
begin
 link:=app_private.order_link(p_token);
 if p_key is null or p_tracking is null or p_tracking !~ '^[a-f0-9]{64}$' then raise exception 'invalid_tracking_key';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 select o.* into result from public.orders o join app_private.order_tracking t on t.order_id=o.id where o.idempotency_key=p_key and t.link_id=link.id;
 if found then
  if result.request_body->>'request_hash'<>request_hash or not exists(select 1 from app_private.order_tracking where order_id=result.id and token_hash=encode(extensions.digest(p_tracking,'sha256'),'hex')) then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',result.id,'number',result.number,'total_cents',result.total_cents,'status',result.status);
 end if;
 select * into limiter from app_private.order_link_secrets where link_id=link.id for update;
 if limiter.window_started<now()-interval '1 minute' then update app_private.order_link_secrets set submissions=0,window_started=now() where link_id=link.id;limiter.submissions:=0;end if;
 if limiter.submissions>=10 then raise exception 'checkout_rate_limit';end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'invalid_items';end if;
 if length(trim(p_contact->>'name')) not between 2 and 100 or length(coalesce(p_contact->>'address',''))>500 or length(coalesce(p_contact->>'email',''))>254 then raise exception 'invalid_contact';end if;
 if link.channel='delivery' and (coalesce(p_contact->>'phone','') !~ '^\+?[0-9]{10,15}$' or length(trim(coalesce(p_contact->>'address','')))<10) then raise exception 'delivery_contact_required';end if;
 if coalesce((p_contact->>'whatsapp_consent')::boolean,false) and coalesce(p_contact->>'phone','') !~ '^\+?[0-9]{10,15}$' then raise exception 'phone_required_for_updates';end if;
 perform 1 from public.products where id in(select x->>'product_id' from jsonb_array_elements(p_items) x) order by id for share;
 for item in select * from jsonb_array_elements(p_items) loop
  select * into product from public.products where id=item->>'product_id' and active;if not found then raise exception 'product_unavailable';end if;
  if coalesce(item->>'quantity','') !~ '^[0-9]+$' then raise exception 'invalid_quantity';end if;qty:=(item->>'quantity')::int;if qty not between 1 and 100 then raise exception 'invalid_quantity';end if;
  mods:=array(select jsonb_array_elements_text(coalesce(item->'modifiers','[]')));
  if not mods<@product.allowed_modifiers or (select count(*) from unnest(mods) x where x like 'Ponto:%')>1 then raise exception 'invalid_modifier';end if;
  if length(coalesce(item->>'notes',''))>500 then raise exception 'notes_too_long';end if;
  total:=total+product.price_cents::bigint*qty;
 end loop;
 if total>1000000 then raise exception 'order_too_large';end if;
 insert into public.orders(source,idempotency_key,request_body,customer,channel,total_cents)
 values('self_service',p_key,jsonb_build_object('request_hash',request_hash),case when link.channel='table' then link.label else 'Delivery' end,link.channel,total) returning * into result;
 for item in select * from jsonb_array_elements(p_items) loop
  select * into product from public.products where id=item->>'product_id';
  insert into public.order_items(order_id,product_id,name,quantity,unit_price_cents,sector,modifiers,notes)
  values(result.id,product.id,product.name,(item->>'quantity')::int,product.price_cents,product.sector,array(select jsonb_array_elements_text(coalesce(item->'modifiers','[]'))),coalesce(item->>'notes',''));
 end loop;
 insert into app_private.order_tracking values(result.id,encode(extensions.digest(p_tracking,'sha256'),'hex'),link.id);
 insert into public.customer_contacts(order_id,name,phone,address,email,whatsapp_consent)
 values(result.id,trim(p_contact->>'name'),coalesce(p_contact->>'phone',''),coalesce(p_contact->>'address',''),coalesce(p_contact->>'email',''),coalesce((p_contact->>'whatsapp_consent')::boolean,false));
 update app_private.order_link_secrets set submissions=submissions+1 where link_id=link.id;
 return jsonb_build_object('id',result.id,'number',result.number,'total_cents',result.total_cents,'status',result.status);
end $$;
create function public.checkout_status(p_tracking text) returns jsonb language plpgsql security definer set search_path='' as $$
declare ord public.orders; attempt public.payment_attempts; artifact app_private.payment_artifacts;
begin
 select o.* into ord from public.orders o join app_private.order_tracking t on t.order_id=o.id where t.token_hash=encode(extensions.digest(p_tracking,'sha256'),'hex');
 if not found then raise exception 'order_unavailable' using errcode='42501';end if;
 select * into attempt from public.payment_attempts where order_id=ord.id order by created_at desc limit 1;
 select * into artifact from app_private.payment_artifacts where attempt_id=attempt.id;
 return jsonb_build_object('id',ord.id,'number',ord.number,'total_cents',ord.total_cents,'status',ord.status,'fulfillment_state',ord.fulfillment_state,'pix',case when artifact.attempt_id is null then null else jsonb_build_object('copyPaste',artifact.copy_paste,'expiresAt',artifact.expires_at) end);
end $$;
create function public.prepare_checkout_payment(p_tracking text,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare ord public.orders; attempt public.payment_attempts;
begin
 select o.* into ord from public.orders o join app_private.order_tracking t on t.order_id=o.id where t.token_hash=encode(extensions.digest(p_tracking,'sha256'),'hex') for update of o;
 if not found or ord.status<>'pending_payment' then raise exception 'payment_not_allowed';end if;
 select * into attempt from public.payment_attempts where order_id=ord.id and status='pending';
 if not found then
  insert into public.payment_attempts(id,order_id,method,amount_cents) values(p_key,ord.id,'pix',ord.total_cents) returning * into attempt;
 end if;
 if attempt.method<>'pix' then raise exception 'payment_reconciliation_required';end if;
 return jsonb_build_object('id',attempt.id,'amount_cents',attempt.amount_cents);
end $$;
create function public.record_pix_artifact(p_attempt uuid,p_code text,p_expires timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.payment_attempts where id=p_attempt and method='pix' and status='pending') or length(p_code) not between 20 and 1000 then raise exception 'invalid_pix_artifact';end if;
 insert into app_private.payment_artifacts values(p_attempt,p_code,p_expires) on conflict(attempt_id) do nothing;
end $$;
create function public.confirm_manual_pix(p_attempt uuid,p_bank_reference text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare payment public.payment_attempts;bankref text:=upper(regexp_replace(coalesce(p_bank_reference,''),'\s+','','g'));
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if bankref !~ '^[A-Z0-9._:-]{8,100}$' then raise exception 'bank_reference_required';end if;
 select * into payment from public.payment_attempts where id=p_attempt for update;
 if not found or payment.method<>'pix' or payment.status not in ('pending','confirmed') then raise exception 'pix_confirmation_not_allowed';end if;
 if payment.status='confirmed' then if payment.provider_reference<>'manual-pix:'||bankref then raise exception 'reference_conflict';end if;return;end if;
 update public.payment_attempts set status='confirmed',provider_reference='manual-pix:'||bankref,confirmed_at=now() where id=p_attempt;
 perform app_private.log('payment.pix_manually_confirmed','order',payment.order_id::text,payment.amount_cents);
 perform app_private.release_order(payment.order_id);
end $$;
create function public.confirm_manual_pix_refund(p_refund uuid,p_bank_reference text) returns void language plpgsql security definer set search_path='' as $$
declare bankref text:=upper(regexp_replace(coalesce(p_bank_reference,''),'\s+','','g'));
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 if bankref !~ '^[A-Z0-9._:-]{8,100}$' or not exists(select 1 from public.refunds r join public.payment_attempts p on p.id=r.payment_id where r.id=p_refund and p.method='pix' and p.provider_reference like 'manual-pix:%') then raise exception 'manual_refund_not_allowed';end if;
 perform app_private.finish_refund(p_refund,'manual-pix-refund:'||bankref);
end $$;

-- Server-side Meta ingestion: private message data is not in Realtime or KDS.
create function public.ingest_whatsapp(p_id text,p_sender text,p_text text,p_received timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare ident uuid;
begin
 if length(p_id) not between 5 and 200 or p_sender !~ '^[0-9]{10,15}$' or length(p_text)>2000 then raise exception 'invalid_message';end if;
 insert into public.whatsapp_inbox(provider_message_id,sender,body,received_at) values(p_id,p_sender,p_text,p_received)
 on conflict(provider_message_id) do nothing returning id into ident;
 if ident is not null then insert into app_private.message_replies(inbox_id) values(ident);end if;
 return ident;
end $$;
create function public.assign_whatsapp(p_id uuid,p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 if not exists(select 1 from public.profiles where id=p_user and active and role in ('admin','cashier')) then raise exception 'invalid_operator';end if;
 update public.whatsapp_inbox set assigned_to=p_user where id=p_id;
 perform app_private.reason('Atribuição de conversa ao operador de atendimento');perform app_private.log('whatsapp.assigned','conversation',p_id::text);
end $$;
-- Claim jobs transactionally; expired leases may retry after a crashed worker.
-- Delivery is at-least-once: Meta has no general send idempotency key. A timeout
-- may duplicate a notification, never a charge or a kitchen ticket.
alter table public.integration_outbox add column lease_until timestamptz;
alter table public.integration_outbox add column last_error text;
create function public.claim_notifications(p_limit int default 10) returns jsonb language plpgsql security definer set search_path='' as $$
declare jobs jsonb;
begin
 with claimed as (
  select o.id from public.integration_outbox o join public.customer_contacts c on c.order_id=o.order_id
  where o.delivered_at is null and o.attempts<8 and o.next_attempt_at<=now() and (o.lease_until is null or o.lease_until<now()) and c.whatsapp_consent and c.erased_at is null and c.phone<>''
  order by o.next_attempt_at for update of o skip locked limit least(greatest(p_limit,1),20)
 ),updated as (
  update public.integration_outbox o set lease_until=now()+interval '2 minutes',attempts=attempts+1 where id in(select id from claimed) returning o.*
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'topic',u.topic,'order_number',ord.number,'phone',c.phone,'attempts',u.attempts,'within_window',exists(select 1 from public.whatsapp_inbox i where i.sender=regexp_replace(c.phone,'[^0-9]','','g') and i.received_at>now()-interval '23 hours'))),'[]') into jobs
 from updated u join public.orders ord on ord.id=u.order_id join public.customer_contacts c on c.order_id=u.order_id;
 return jobs;
end $$;
create function public.finish_notification(p_id uuid,p_success boolean,p_error text default null) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.integration_outbox set delivered_at=case when p_success then now() else null end,lease_until=null,
 next_attempt_at=now()+make_interval(secs=>least(3600,30*power(2,least(attempts,7))::int)),last_error=case when p_success then null else left(p_error,80) end where id=p_id and lease_until is not null;
end $$;
create function public.claim_message_replies() returns jsonb language plpgsql security definer set search_path='' as $$
declare jobs jsonb;
begin
 with pending as(select id from app_private.message_replies where state in ('pending','retry','running') and attempts<8 and next_attempt_at<=now() and (lease_until is null or lease_until<now()) order by next_attempt_at for update skip locked limit 10),claimed as(
 update app_private.message_replies set state='running',lease_until=now()+interval '2 minutes',attempts=attempts+1 where id in(select id from pending) returning * )
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'sender',i.sender,'body',i.body,'received_at',i.received_at)),'[]') into jobs from claimed c join public.whatsapp_inbox i on i.id=c.inbox_id;
 return jobs;
end $$;
create function public.finish_message_reply(p_id uuid,p_success boolean) returns void language plpgsql security definer set search_path='' as $$
begin update app_private.message_replies set state=case when p_success then 'delivered' else 'retry' end,lease_until=null,next_attempt_at=now()+interval '5 minutes' where id=p_id and state='running';end $$;

alter table public.order_links enable row level security;
create policy links_admin on public.order_links for select to authenticated using(app_private.is_admin());
grant select on public.order_links to authenticated;
revoke all on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.role(),app_private.is_admin(),app_private.can_operate(),app_private.terminal_open() to authenticated;
grant execute on function public.create_order_link(text,text,int,text),public.revoke_order_link(uuid,text),public.confirm_manual_pix(uuid,text,text),public.confirm_manual_pix_refund(uuid,text),public.assign_whatsapp(uuid,uuid) to authenticated;
grant execute on function public.checkout_menu(text),public.checkout_order(text,uuid,text,jsonb,jsonb),public.checkout_status(text) to anon,authenticated;
grant execute on function public.prepare_checkout_payment(text,uuid),public.record_pix_artifact(uuid,text,timestamptz),public.ingest_whatsapp(text,text,text,timestamptz),public.claim_notifications(int),public.finish_notification(uuid,boolean,text),public.claim_message_replies(),public.finish_message_reply(uuid,boolean) to service_role;

-- SOURCE: supabase/migrations/202611050005_reports.sql
-- SHA256: a14dba06e369a4743a2cbf454bc7fd243b0f7e6e87a9bd7564f8cfe137808ab1
create function public.admin_metrics(p_from timestamptz,p_to timestamptz) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; peaks jsonb;margins jsonb;bottlenecks jsonb;low_stock jsonb;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<=p_from or p_to-p_from>interval '366 days' then raise exception 'invalid_period';end if;
 select jsonb_build_object('paid_orders',count(*) filter(where paid_at is not null and status<>'cancelled'),'revenue_cents',coalesce(sum(total_cents) filter(where paid_at is not null and status<>'cancelled'),0),'discounts_cents',coalesce(sum(discount_cents) filter(where paid_at is not null and status<>'cancelled'),0),'cancelled',count(*) filter(where status='cancelled')) into result from public.orders where created_at>=p_from and created_at<p_to;
 select coalesce(jsonb_agg(row_to_json(x)),'[]') into peaks from(select extract(hour from paid_at at time zone 'America/Recife')::int as "hour",count(*) orders,sum(total_cents) revenue_cents from public.orders where paid_at>=p_from and paid_at<p_to and status<>'cancelled' group by 1 order by 1) x;
 select coalesce(jsonb_agg(row_to_json(x)),'[]') into margins from(
  with costs as(select r.product_id,sum(r.quantity*i.unit_cost_cents) cost_cents from public.recipe_items r join public.ingredients i on i.id=r.ingredient_id group by 1)
  select p.id,p.name,p.price_cents,c.cost_cents,p.price_cents-c.cost_cents margin_cents,coalesce(sold.quantity,0) quantity from public.products p left join costs c on c.product_id=p.id
  left join(select i.product_id,sum(i.quantity) quantity from public.order_items i join public.orders o on o.id=i.order_id where o.paid_at>=p_from and o.paid_at<p_to and o.status<>'cancelled' group by i.product_id) sold on sold.product_id=p.id order by margin_cents desc nulls last
 ) x;
 select coalesce(jsonb_agg(row_to_json(x)),'[]') into bottlenecks from(select sector,count(*) completed,round(avg(extract(epoch from started_at-created_at))) queue_seconds,round(avg(extract(epoch from ready_at-started_at))) prep_seconds from public.kitchen_tickets where ready_at>=p_from and ready_at<p_to and started_at is not null and status='ready' group by sector) x;
 select coalesce(jsonb_agg(row_to_json(x)),'[]') into low_stock from(select id,name,unit,stock,minimum_stock from public.ingredients where stock<=minimum_stock order by stock) x;
 perform app_private.reason('Consulta de indicadores agregados pelo administrador');perform app_private.log('report.viewed','report',p_from::text||'/'||p_to::text);
 return result||jsonb_build_object('cancelled_credit_cents',(select coalesce(sum(p.amount_cents),0) from public.payment_attempts p join public.orders o on o.id=p.order_id where o.status='cancelled' and p.status='confirmed'),'peaks',peaks,'margins',margins,'bottlenecks',bottlenecks,'low_stock',low_stock);
end $$;
grant execute on function public.admin_metrics(timestamptz,timestamptz) to authenticated;

-- SOURCE: supabase/migrations/202611050006_staff_and_jobs.sql
-- SHA256: 6ab32904a92e78fdf075a14543b6c096a5c66b7150c177f580dbce9c677fd5a4
revoke execute on function public.manage_staff(uuid,public.app_role,public.sector,boolean) from authenticated;
create function public.manage_staff(p_user uuid,p_role public.app_role,p_sector public.sector,p_active boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 perform public.manage_staff(p_user,p_role,p_sector,p_active);
end $$;
create function public.retry_notification(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 update public.integration_outbox set attempts=0,next_attempt_at=now(),lease_until=null,last_error=null where id=p_id and delivered_at is null and (lease_until is null or lease_until<now());
 perform app_private.log('notification.retry','outbox',p_id::text);
end $$;
create function public.record_whatsapp_reply(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() and not (app_private.can_operate() and exists(select 1 from public.whatsapp_inbox where id=p_id and assigned_to=auth.uid() and closed_at is null)) then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason('Resposta de atendimento enviada pelo operador');perform app_private.log('whatsapp.reply','conversation',p_id::text);
end $$;
grant execute on function public.manage_staff(uuid,public.app_role,public.sector,boolean,text),public.retry_notification(uuid,text),public.record_whatsapp_reply(uuid) to authenticated;

-- SOURCE: supabase/migrations/202611050007_recipes_and_drawers.sql
-- SHA256: 12c87f245e6073cb034ebe9ad6bea683644696fb0be0a7ff2f33286ce7eddfe4
create table public.recipe_modifier_rules(
 product_id text not null references public.products(id),modifier text not null,ingredient_id uuid not null references public.ingredients(id),
 quantity_delta numeric(12,3) not null check(quantity_delta<>0),primary key(product_id,modifier,ingredient_id)
);
alter table public.recipe_modifier_rules enable row level security;
create policy modifier_rules_admin on public.recipe_modifier_rules for select to authenticated using(app_private.is_admin());
grant select on public.recipe_modifier_rules to authenticated;
create function app_private.audit_modifier_recipe() returns trigger language plpgsql security definer set search_path='' as $$
begin perform app_private.log('recipe.modifier_changed','product',case when tg_op='DELETE' then old.product_id else new.product_id end);if tg_op='DELETE' then return old;end if;return new;end $$;
create trigger modifier_recipe_audit after insert or update or delete on public.recipe_modifier_rules for each row execute function app_private.audit_modifier_recipe();
revoke execute on function public.save_recipe(text,jsonb,text) from authenticated;
create function public.save_recipe(p_product text,p_items jsonb,p_rules jsonb,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare rule jsonb; allowed text[];
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if jsonb_typeof(p_rules)<>'array' or jsonb_array_length(p_rules)>100 then raise exception 'invalid_recipe_rules';end if;
 select allowed_modifiers into allowed from public.products where id=p_product for update;if not found then raise exception 'product_not_found';end if;
 delete from public.recipe_modifier_rules where product_id=p_product;
 perform public.save_recipe(p_product,p_items,p_reason);
 for rule in select * from jsonb_array_elements(p_rules) loop
  if not (rule->>'modifier')=any(allowed) or coalesce(rule->>'quantity_delta','') !~ '^-?[0-9]+(\.[0-9]{1,3})?$' then raise exception 'invalid_recipe_rule';end if;
  insert into public.recipe_modifier_rules values(p_product,rule->>'modifier',(rule->>'ingredient_id')::uuid,(rule->>'quantity_delta')::numeric);
 end loop;
end $$;
create function app_private.order_consumption(p_order uuid) returns table(ingredient_id uuid,quantity numeric) language sql stable security definer set search_path='' as $$
 with ingredient_options as(
  select i.id item_id,r.ingredient_id from public.order_items i join public.recipe_items r on r.product_id=i.product_id where i.order_id=p_order
  union
  select i.id,m.ingredient_id from public.order_items i join public.recipe_modifier_rules m on m.product_id=i.product_id and m.modifier=any(i.modifiers) where i.order_id=p_order
 ),consumption as(
 select opt.ingredient_id,i.quantity*greatest(0,
  coalesce((select r.quantity from public.recipe_items r where r.product_id=i.product_id and r.ingredient_id=opt.ingredient_id),0)+
  coalesce((select sum(m.quantity_delta) from public.recipe_modifier_rules m where m.product_id=i.product_id and m.ingredient_id=opt.ingredient_id and m.modifier=any(i.modifiers)),0)
 ) quantity from ingredient_options opt join public.order_items i on i.id=opt.item_id
 )select c.ingredient_id,sum(c.quantity) from consumption c group by c.ingredient_id having sum(c.quantity)>0
$$;
create or replace function app_private.release_order(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare ord public.orders; consumption record;
begin
 select * into ord from public.orders where id=p_order for update;
 if ord.status<>'pending_payment' then return;end if;
 if not exists(select 1 from public.payment_attempts where order_id=p_order and status='confirmed') then raise exception 'payment_required';end if;
 perform app_private.reason('Baixa por venda confirmada com ficha e modificadores');
 perform 1 from public.products where id in(select product_id from public.order_items where order_id=p_order) order by id for share;
 perform 1 from public.ingredients where id in(select x.ingredient_id from app_private.order_consumption(p_order) x) order by id for update;
 for consumption in select * from app_private.order_consumption(p_order) loop
  insert into public.stock_movements(order_id,ingredient_id,quantity) values(p_order,consumption.ingredient_id,-consumption.quantity);
  update public.ingredients set stock=stock-consumption.quantity where id=consumption.ingredient_id;
 end loop;
 insert into public.kitchen_tickets(order_id,order_number,customer,sector,items)
 select ord.id,ord.number,ord.customer,i.sector,jsonb_agg(jsonb_build_object('name',i.name,'quantity',i.quantity,'modifiers',i.modifiers,'notes',i.notes) order by i.id)
 from public.order_items i where i.order_id=p_order group by i.sector;
 update public.orders set status='queued',paid_at=now() where id=p_order;
 insert into public.integration_outbox(topic,order_id) values('order.paid',p_order) on conflict do nothing;
end $$;
revoke execute on function public.close_shift(uuid,int) from authenticated;
create function public.close_shift(p_shift uuid,p_counted_cents int,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin perform app_private.reason(p_reason);perform public.close_shift(p_shift,p_counted_cents);end $$;
create function app_private.audit_shift() returns trigger language plpgsql security definer set search_path='' as $$
declare expected bigint;
begin
 if tg_op='INSERT' then
  perform app_private.reason('Abertura de caixa com fundo de troco declarado');
  perform app_private.log('shift.opened','shift',new.id::text,new.opening_cents);
 elsif old.closed_at is null and new.closed_at is not null then
  expected:=(public.cash_summary(new.id)->>'expected_cents')::bigint;
  perform app_private.log('shift.closed','shift',new.id::text,new.closing_counted_cents-expected);
 end if;return new;
end $$;
create trigger shift_audit after insert or update on public.shifts for each row execute function app_private.audit_shift();
revoke all on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.role(),app_private.is_admin(),app_private.can_operate(),app_private.terminal_open() to authenticated;
grant execute on function public.save_recipe(text,jsonb,jsonb,text),public.close_shift(uuid,int,text) to authenticated;

-- SOURCE: supabase/migrations/202611050008_message_audit.sql
-- SHA256: e410a33d0214a97d578f8c3bc88b69fd91bb52e088b65822487262ce736d5094
revoke execute on function public.record_whatsapp_reply(uuid) from authenticated;
create function public.record_whatsapp_reply(p_id uuid,p_actor uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles p join public.whatsapp_inbox i on i.id=p_id where p.id=p_actor and p.active and (p.role='admin' or (p.role='cashier' and i.assigned_to=p_actor and i.closed_at is null))) then raise exception 'access_denied' using errcode='42501';end if;
 insert into public.audit_log(actor_id,action,entity_type,entity_key,justification,actor_kind) values(p_actor,'whatsapp.reply','conversation',p_id::text,'Resposta enviada pela API oficial por operador autorizado','user');
end $$;
grant execute on function public.record_whatsapp_reply(uuid,uuid) to service_role;

-- SOURCE: supabase/migrations/202611050009_account_audit.sql
-- SHA256: fcd201bfd5be09616b6378b05200bb8fef16f2f4a06f6457d7018509b8411c97
create function app_private.audit_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  perform app_private.reason('Nova conta inativa criada pelo serviço de autenticação');
  perform app_private.log('profile.created','profile',new.id::text);
 elsif (old.role,old.active,old.sector) is distinct from (new.role,new.active,new.sector) then
  perform app_private.log('profile.access_changed','profile',new.id::text);
 end if;return new;
end $$;
create trigger profile_audit after insert or update on public.profiles for each row execute function app_private.audit_profile();
create or replace function public.manage_staff(p_user uuid,p_role public.app_role,p_sector public.sector,p_active boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 perform 1 from public.profiles order by id for update;
 if not exists(select 1 from public.profiles where id=p_user) then raise exception 'user_not_found';end if;
 if exists(select 1 from public.profiles where id=p_user and active and role='admin') and (p_role<>'admin' or not p_active)
 and not exists(select 1 from public.profiles where active and role='admin' and id<>p_user) then raise exception 'last_admin';end if;
 update public.profiles set role=p_role,sector=p_sector,active=p_active where id=p_user;
 delete from app_private.terminal_leases where user_id=p_user;
end $$;
-- Once issued, the payment code is stable even if merchant settings change.
create or replace function public.record_pix_artifact(p_attempt uuid,p_code text,p_expires timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.payment_attempts where id=p_attempt and method='pix' and status='pending') or length(p_code) not between 20 and 1000 then raise exception 'invalid_pix_artifact';end if;
 insert into app_private.payment_artifacts values(p_attempt,p_code,p_expires) on conflict(attempt_id) do nothing;
 if not exists(select 1 from app_private.payment_artifacts where attempt_id=p_attempt and copy_paste=p_code and expires_at is not distinct from p_expires) then raise exception 'pix_configuration_changed_reconcile';end if;
end $$;

-- SOURCE: supabase/migrations/202611050010_manual_pix_reconciliation.sql
-- SHA256: 065344bf0969a18ac03ba9d50883f301bbb8fa49685f9369af8dd9244e555a6d
alter table public.payment_attempts add column confirmation_mode text not null default 'provider' check(confirmation_mode in ('provider','cash','manual_pix'));
update public.payment_attempts set confirmation_mode='cash' where method='cash';
create function app_private.payment_mode() returns trigger language plpgsql set search_path='' as $$
begin if new.method='cash' then new.confirmation_mode:='cash';end if;return new;end $$;
create trigger payment_mode before insert on public.payment_attempts for each row execute function app_private.payment_mode();
create or replace function public.record_pix_artifact(p_attempt uuid,p_code text,p_expires timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.payment_attempts where id=p_attempt and method='pix' and status='pending' for update;
 if not found or length(p_code) not between 20 and 1000 then raise exception 'invalid_pix_artifact';end if;
 insert into app_private.payment_artifacts values(p_attempt,p_code,p_expires) on conflict(attempt_id) do nothing;
 if not exists(select 1 from app_private.payment_artifacts where attempt_id=p_attempt and copy_paste=p_code and expires_at is not distinct from p_expires) then raise exception 'pix_configuration_changed_reconcile';end if;
 update public.payment_attempts set confirmation_mode=case when p_expires is null then 'manual_pix' else 'provider' end where id=p_attempt;
end $$;
create or replace function public.confirm_manual_pix(p_attempt uuid,p_bank_reference text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare payment public.payment_attempts;bankref text:=upper(regexp_replace(coalesce(p_bank_reference,''),'\s+','','g'));ord public.orders;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if bankref !~ '^[A-Z0-9._:-]{8,100}$' then raise exception 'bank_reference_required';end if;
 select * into payment from public.payment_attempts where id=p_attempt for update;
 if not found or payment.method<>'pix' or payment.confirmation_mode<>'manual_pix' or payment.status not in ('pending','failed','confirmed') then raise exception 'pix_confirmation_not_allowed';end if;
 if payment.status='confirmed' then if payment.provider_reference<>'manual-pix:'||bankref then raise exception 'reference_conflict';end if;return;end if;
 select * into ord from public.orders where id=payment.order_id for update;
 update public.payment_attempts set status='confirmed',provider_reference='manual-pix:'||bankref,confirmed_at=now() where id=p_attempt;
 perform app_private.log(case when ord.status='cancelled' then 'payment.pix_late_received' else 'payment.pix_manually_confirmed' end,'order',payment.order_id::text,payment.amount_cents);
 -- release_order deliberately does nothing for a cancelled order. A real late
 -- credit is recorded financially and can be refunded, never cooked silently.
 perform app_private.release_order(payment.order_id);
end $$;
create function public.void_pending_manual_pix(p_order uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare ord public.orders;attempt public.payment_attempts;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 select * into ord from public.orders where id=p_order for update;if not found then raise exception 'order_unavailable';end if;
 if ord.status='cancelled' then return;end if;
 if ord.status<>'pending_payment' then raise exception 'order_already_paid';end if;
 select * into attempt from public.payment_attempts where order_id=p_order and status='pending' for update;
 if not found or attempt.method<>'pix' or attempt.confirmation_mode<>'manual_pix' or attempt.provider_reference is not null then raise exception 'provider_reconciliation_required';end if;
 update public.payment_attempts set status='failed' where id=attempt.id;
 update public.orders set status='cancelled' where id=p_order;
 perform app_private.log('payment.manual_pix_closed_without_credit','order',p_order::text);
 insert into public.integration_outbox(topic,order_id) values('order.cancelled',p_order) on conflict do nothing;
end $$;
grant execute on function public.void_pending_manual_pix(uuid,text) to authenticated;
create or replace function public.confirm_provider_payment(p_attempt uuid,p_amount int,p_reference text,p_provider text,p_event text,p_payload_hash text) returns void language plpgsql security definer set search_path='' as $$
declare attempt public.payment_attempts; previous_hash text; previous_attempt uuid;
begin
 select * into attempt from public.payment_attempts where id=p_attempt for update;
 if not found or p_amount is null or coalesce(p_reference,'')='' or coalesce(p_provider,'')='' or coalesce(p_event,'')='' or coalesce(p_payload_hash,'')='' or (attempt.method='cash' or attempt.confirmation_mode<>'provider') or attempt.amount_cents<>p_amount or attempt.status not in ('pending','confirmed') then raise exception 'invalid_provider_payment'; end if;
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

-- SOURCE: supabase/migrations/202611050011_operations.sql
-- SHA256: e332bee5b8bb667cd7b60b7efaaea47c3db4626201a7af51f449bf25f99c0064
create or replace function public.cash_movement(p_shift uuid,p_kind text,p_amount int,p_reason text,p_key uuid) returns void language plpgsql security definer set search_path='' as $$
declare previous public.cash_movements; balance bigint; turn public.shifts;
begin
 if not app_private.can_operate() or (p_kind='supply' and not app_private.is_admin()) then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if p_kind not in ('withdrawal','supply') or p_amount is null or p_amount<=0 then raise exception 'invalid_cash_movement';end if;
 select * into turn from public.shifts where id=p_shift and cashier_id=auth.uid() for update;if not found then raise exception 'shift_unavailable';end if;
 select * into previous from public.cash_movements where id=p_key;
 if found then if (previous.shift_id,previous.actor_id,previous.kind,previous.amount_cents,previous.justification) is distinct from (p_shift,auth.uid(),p_kind,p_amount,trim(p_reason)) then raise exception 'idempotency_conflict';end if;return;end if;
 if turn.closed_at is not null then raise exception 'shift_unavailable';end if;
 balance:=(public.cash_summary(p_shift)->>'expected_cents')::bigint;
 if p_kind='withdrawal' and p_amount>balance then raise exception 'insufficient_cash';end if;
 insert into public.cash_movements(id,shift_id,actor_id,kind,amount_cents,justification) values(p_key,p_shift,auth.uid(),p_kind,p_amount,trim(p_reason));
end $$;
drop policy inbox_need_to_know on public.whatsapp_inbox;
create policy inbox_need_to_know on public.whatsapp_inbox for select to authenticated using(app_private.is_admin() or (app_private.can_operate() and assigned_to=auth.uid() and closed_at is null and received_at>now()-interval '24 hours'));
create function public.close_conversation(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() and not (app_private.can_operate() and exists(select 1 from public.whatsapp_inbox where id=p_id and assigned_to=auth.uid() and closed_at is null and received_at>now()-interval '24 hours')) then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 update public.whatsapp_inbox set closed_at=now() where id=p_id and closed_at is null;
 perform app_private.log('whatsapp.closed','conversation',p_id::text);
end $$;
grant execute on function public.close_conversation(uuid,text) to authenticated;

-- SOURCE: supabase/migrations/202611050012_fastpass.sql
-- SHA256: 686ea5b0c8846f0fcc8dc88bdddc28b8c30968215ce8a1ee7dc62a6e8ba11e25
-- PIN identifica apenas funcionários; o Auth continua sendo a autoridade da sessão.
create table app_private.fastpass_challenges (
 token_hash text primary key, user_id uuid not null references public.profiles(id) on delete cascade,
 terminal_id uuid not null references public.terminals(id), credential_version text not null, expires_at timestamptz not null default now()+interval '60 seconds'
);
create table app_private.fastpass_sessions (
 user_id uuid not null references public.profiles(id) on delete cascade,
 session_id text not null unique, terminal_id uuid not null references public.terminals(id),
 created_at timestamptz not null default now(), primary key(user_id,session_id)
);
alter table app_private.fastpass_challenges enable row level security;
alter table app_private.fastpass_sessions enable row level security;
revoke all on app_private.fastpass_challenges,app_private.fastpass_sessions from public,anon,authenticated,service_role;

-- Uma sessão criada por PIN jamais adquire privilégios de admin, mesmo após promoção.
create or replace function app_private.role() returns public.app_role language sql stable security definer set search_path='' as $$
 select p.role from public.profiles p where p.id=auth.uid() and p.active
 and not (p.role='admin' and exists(select 1 from app_private.fastpass_sessions s
   where s.user_id=p.id and s.session_id=auth.jwt()->>'session_id'))
$$;
create function public.operator_context() returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(p)||jsonb_build_object('requires_password',p.role='admin' and exists(
   select 1 from app_private.fastpass_sessions s where s.user_id=p.id and s.session_id=auth.jwt()->>'session_id'))
 from public.profiles p where p.id=auth.uid()
$$;
revoke all on function public.operator_context() from public,anon,authenticated;
grant execute on function public.operator_context() to authenticated;

create or replace function public.set_staff_pin(p_user uuid,p_pin text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 if p_pin is null or p_pin !~ '^[0-9]{4}$' or not exists(select 1 from public.profiles where id=p_user and active) then raise exception 'invalid_staff_pin'; end if;
 perform pg_advisory_xact_lock(638194501);
 if exists(select 1 from public.profiles where id=p_user and role in ('cashier','kitchen')) and exists(
   select 1 from app_private.pin_credentials c join public.profiles p on p.id=c.user_id
   where c.user_id<>p_user and p.active and p.role in ('cashier','kitchen') and extensions.crypt(p_pin,c.pin_hash)=c.pin_hash
 ) then raise exception 'staff_pin_in_use'; end if;
 insert into app_private.pin_credentials(user_id,pin_hash) values(p_user,extensions.crypt(p_pin,extensions.gen_salt('bf',10)))
 on conflict(user_id) do update set pin_hash=excluded.pin_hash,failures=0,locked_until=null;
 delete from app_private.terminal_leases where user_id=p_user;
 delete from app_private.fastpass_challenges where user_id=p_user;
 perform app_private.reason('Definição ou troca de PIN individual do terminal');
 perform app_private.log('staff.pin_changed','profile',p_user::text);
end $$;

-- Chamável SOMENTE pelo Edge Function; nunca retorna hashes ou e-mail ao navegador.
create function public.authenticate_staff_pin(p_pin text,p_terminal_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare device uuid; attempts app_private.terminal_attempts; matches uuid[]; versions text[]; ticket text;
begin
 if p_terminal_token is null or p_terminal_token !~ '^[a-f0-9]{64}$' then
   return jsonb_build_object('ok',false,'error','TERMINAL_REQUIRED'); end if;
 select s.terminal_id into device from app_private.terminal_secrets s join public.terminals t on t.id=s.terminal_id
 where s.token_hash=encode(extensions.digest(p_terminal_token,'sha256'),'hex') and t.active;
 if not found then return jsonb_build_object('ok',false,'error','TERMINAL_REQUIRED'); end if;
 select * into attempts from app_private.terminal_attempts where terminal_id=device for update;
 if attempts.locked_until>now() then return jsonb_build_object('ok',false,'error','PIN_LOCKED','retry_at',attempts.locked_until); end if;
 if p_pin ~ '^[0-9]{4}$' then
   select array_agg(c.user_id),array_agg(encode(extensions.digest(c.pin_hash,'sha256'),'hex')) into matches,versions from app_private.pin_credentials c join public.profiles p on p.id=c.user_id
   where p.active and p.role in ('cashier','kitchen') and (c.locked_until is null or c.locked_until<=now())
   and extensions.crypt(p_pin,c.pin_hash)=c.pin_hash;
 end if;
 -- PINs legados duplicados falham fechados; o administrador deve definir PINs distintos.
 if coalesce(cardinality(matches),0)<>1 then
   update app_private.terminal_attempts set failures=case when failures=4 then 0 else failures+1 end,
    locked_until=case when failures=4 then now()+interval '3 minutes' else null end
    where terminal_id=device returning * into attempts;
   if attempts.locked_until is not null then
     perform app_private.reason('Cinco tentativas incorretas no acesso Fast-Pass');
     perform app_private.log('terminal.pin_lockout','terminal',device::text);
   end if;
   return jsonb_build_object('ok',false,'error',case when attempts.locked_until is null then 'INVALID_PIN' else 'PIN_LOCKED' end,'retry_at',attempts.locked_until);
 end if;
 update app_private.terminal_attempts set failures=0,locked_until=null where terminal_id=device;
 ticket:=encode(extensions.gen_random_bytes(32),'hex');
 delete from app_private.fastpass_challenges where expires_at<=now();
 insert into app_private.fastpass_challenges(token_hash,user_id,terminal_id,credential_version)
 values(encode(extensions.digest(ticket,'sha256'),'hex'),matches[1],device,versions[1]);
 return jsonb_build_object('ok',true,'user_id',matches[1],'challenge',ticket);
end $$;
create function public.bind_fastpass_session(p_user uuid,p_session_id text,p_challenge text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare challenge app_private.fastpass_challenges; expiry timestamptz:=now()+interval '10 minutes';
begin
 if p_session_id is null or p_session_id !~ '^[a-f0-9-]{36}$' or p_challenge is null or p_challenge !~ '^[a-f0-9]{64}$' then raise exception 'access_denied' using errcode='42501'; end if;
 select c.* into challenge from app_private.fastpass_challenges c join public.terminals t on t.id=c.terminal_id and t.active
   join public.profiles p on p.id=c.user_id and p.active and p.role in ('cashier','kitchen')
   join app_private.pin_credentials pin on pin.user_id=c.user_id and encode(extensions.digest(pin.pin_hash,'sha256'),'hex')=c.credential_version
 where c.token_hash=encode(extensions.digest(p_challenge,'sha256'),'hex') and c.user_id=p_user and c.expires_at>now() for update of c for share of pin;
 if not found then raise exception 'access_denied' using errcode='42501'; end if;
 delete from app_private.fastpass_challenges where token_hash=challenge.token_hash;
 insert into app_private.fastpass_sessions(user_id,session_id,terminal_id) values(p_user,p_session_id,challenge.terminal_id);
 insert into app_private.terminal_leases(user_id,session_id,expires_at,terminal_id) values(p_user,p_session_id,expiry,challenge.terminal_id)
 on conflict(user_id,session_id) do update set expires_at=excluded.expires_at,terminal_id=excluded.terminal_id;
 perform app_private.reason('Entrada individual Fast-Pass em terminal cadastrado');
 perform app_private.log('staff.fastpass_login','profile',p_user::text);
 return jsonb_build_object('ok',true,'expires_at',expiry);
end $$;
revoke all on function public.authenticate_staff_pin(text,text),public.bind_fastpass_session(uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.authenticate_staff_pin(text,text),public.bind_fastpass_session(uuid,text,text) to service_role;

-- SOURCE: supabase/migrations/202611050013_kitchen_demand.sql
-- SHA256: fd0011f34075a6ef6b0b40b97a186338ce6127939163e804bb08b1fdc8a7bab9
create table public.kitchen_station_settings (
 sector public.sector primary key, reference_unit_seconds int not null check(reference_unit_seconds between 10 and 3600),
 parallel_capacity int not null check(parallel_capacity between 1 and 30), critical_items int not null check(critical_items between 1 and 999),
 updated_at timestamptz not null default now()
);
-- Referências iniciais editáveis; não representam tempos já medidos da lanchonete.
insert into public.kitchen_station_settings values('grill',180,3,15,now()),('fryer',240,2,15,now()),('bar',60,4,20,now());
create table public.kitchen_station_load (
 sector public.sector primary key references public.kitchen_station_settings(sector),
 queued_items int not null default 0, preparing_items int not null default 0,
 average_unit_seconds numeric not null, reference_unit_seconds int not null, sample_count int not null default 0,
 parallel_capacity int not null, critical_items int not null, updated_at timestamptz not null default now()
);
alter table public.kitchen_station_settings enable row level security;
alter table public.kitchen_station_load enable row level security;
create policy station_settings_admin on public.kitchen_station_settings for select to authenticated using(app_private.is_admin());
create policy station_load_read on public.kitchen_station_load for select to authenticated using(
 app_private.is_admin() or (app_private.role() in ('cashier','kitchen') and app_private.terminal_open()));
revoke all on public.kitchen_station_settings,public.kitchen_station_load from public,anon,authenticated,service_role;
grant select on public.kitchen_station_settings,public.kitchen_station_load to authenticated;
create index kitchen_active_sector_idx on public.kitchen_tickets(sector,status) where status in ('queued','preparing');
create index kitchen_recent_ready_idx on public.kitchen_tickets(sector,ready_at desc) where status='ready' and started_at is not null;

create function app_private.rebuild_kitchen_load() returns trigger language plpgsql security definer set search_path='' as $$
declare station public.kitchen_station_settings; queued int; preparing int; measured numeric; samples int;
begin
 -- Os três registros são bloqueados na mesma ordem antes do recálculo. O SELECT
 -- seguinte vê os commits precedentes, evitando perda de contagem entre caixas.
 perform 1 from public.kitchen_station_load order by sector for update;
 for station in select * from public.kitchen_station_settings order by sector loop
   select coalesce(sum(units) filter(where status='queued'),0),coalesce(sum(units) filter(where status='preparing'),0)
   into queued,preparing from (
     select t.status,(select sum((i->>'quantity')::int) from jsonb_array_elements(t.items) i) units
     from public.kitchen_tickets t where t.sector=station.sector and t.status in ('queued','preparing')
   ) active;
   -- Até 100 tickets concluídos nos últimos 30 dias, ponderados por quantidade.
   select round(sum(seconds)/nullif(sum(units),0),2),count(*) into measured,samples from (
     select extract(epoch from ready_at-started_at) seconds,
       (select sum((i->>'quantity')::int) from jsonb_array_elements(items) i) units
     from public.kitchen_tickets where sector=station.sector and status='ready'
       and ready_at>now()-interval '30 days' and ready_at>started_at
     order by ready_at desc limit 100
   ) recent where units>0;
   insert into public.kitchen_station_load(sector,queued_items,preparing_items,average_unit_seconds,reference_unit_seconds,sample_count,parallel_capacity,critical_items)
   values(station.sector,queued,preparing,coalesce(measured,station.reference_unit_seconds),station.reference_unit_seconds,samples,station.parallel_capacity,station.critical_items)
   on conflict(sector) do update set queued_items=excluded.queued_items,preparing_items=excluded.preparing_items,
     average_unit_seconds=excluded.average_unit_seconds,reference_unit_seconds=excluded.reference_unit_seconds,sample_count=excluded.sample_count,
     parallel_capacity=excluded.parallel_capacity,critical_items=excluded.critical_items,updated_at=clock_timestamp()
   where (kitchen_station_load.queued_items,kitchen_station_load.preparing_items,kitchen_station_load.average_unit_seconds,
     kitchen_station_load.reference_unit_seconds,kitchen_station_load.sample_count,kitchen_station_load.parallel_capacity,kitchen_station_load.critical_items)
    is distinct from (excluded.queued_items,excluded.preparing_items,excluded.average_unit_seconds,excluded.reference_unit_seconds,excluded.sample_count,excluded.parallel_capacity,excluded.critical_items);
 end loop;
 return null;
end $$;
-- Pré-cria as três linhas para que o lock tenha sempre um alvo, inclusive na primeira venda.
insert into public.kitchen_station_load(sector,average_unit_seconds,reference_unit_seconds,parallel_capacity,critical_items)
select sector,reference_unit_seconds,reference_unit_seconds,parallel_capacity,critical_items from public.kitchen_station_settings;
create trigger kitchen_load_changed after insert or update or delete on public.kitchen_tickets
for each statement execute function app_private.rebuild_kitchen_load();
create trigger kitchen_settings_changed after update on public.kitchen_station_settings
for each statement execute function app_private.rebuild_kitchen_load();
-- Dispara também o preenchimento inicial para tickets anteriores à migração.
update public.kitchen_station_settings set updated_at=now();

create function public.kitchen_load_snapshot() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() and (app_private.role() is null or app_private.role() not in ('cashier','kitchen') or not app_private.terminal_open()) then
   raise exception 'access_denied' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(s) order by sector) from public.kitchen_station_load s),'[]');
end $$;
create function public.set_kitchen_station(p_sector public.sector,p_seconds int,p_capacity int,p_critical int,p_reason text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 perform app_private.reason(p_reason);
 update public.kitchen_station_settings set reference_unit_seconds=p_seconds,parallel_capacity=p_capacity,
   critical_items=p_critical,updated_at=now() where sector=p_sector;
 perform app_private.log('kitchen.capacity_changed','sector',p_sector::text);
end $$;
revoke all on function app_private.rebuild_kitchen_load() from public,anon,authenticated,service_role;
revoke all on function public.kitchen_load_snapshot(),public.set_kitchen_station(public.sector,int,int,int,text) from public,anon,authenticated,service_role;
grant execute on function public.kitchen_load_snapshot(),public.set_kitchen_station(public.sector,int,int,int,text) to authenticated;
alter publication supabase_realtime add table public.kitchen_station_load;

-- SOURCE: supabase/migrations/202611050014_management_dre.sql
-- SHA256: 930d2d6284b09170b4aff4f295fac69aff3bf1a6f0887713fd07211cbc4f9428
-- Custo da unidade no momento da baixa. Registros antigos ficam NULL, sem inventar histórico.
alter table public.stock_movements add column unit_cost_snapshot_cents int check(unit_cost_snapshot_cents>=0);
create function app_private.snapshot_ingredient_cost() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select unit_cost_cents into new.unit_cost_snapshot_cents from public.ingredients where id=new.ingredient_id;
 return new;
end $$;
create trigger stock_cost_snapshot before insert on public.stock_movements for each row execute function app_private.snapshot_ingredient_cost();
create table public.operating_expenses (
 id uuid primary key, description text not null check(length(trim(description)) between 2 and 150),
 amount_cents int not null check(amount_cents>0), expense_date date not null,
 justification text not null check(length(trim(justification)) between 5 and 500),
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
alter table public.operating_expenses enable row level security;
create policy operating_expenses_admin on public.operating_expenses for select to authenticated using(app_private.is_admin());
revoke all on public.operating_expenses from public,anon,authenticated,service_role;
grant select on public.operating_expenses to authenticated;
create index operating_expense_date_idx on public.operating_expenses(expense_date);
create trigger expense_immutable before update or delete or truncate on public.operating_expenses
for each statement execute function app_private.immutable_log();
create function public.record_operating_expense(p_key uuid,p_description text,p_amount int,p_date date,p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare previous public.operating_expenses;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 perform app_private.reason(p_reason);
 perform pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 select * into previous from public.operating_expenses where id=p_key;
 if found then
   if (previous.description,previous.amount_cents,previous.expense_date,previous.justification) is distinct from(trim(p_description),p_amount,p_date,trim(p_reason)) then raise exception 'idempotency_conflict'; end if;
   return previous.id;
 end if;
 insert into public.operating_expenses(id,description,amount_cents,expense_date,justification,created_by)
 values(p_key,trim(p_description),p_amount,p_date,trim(p_reason),auth.uid());
 perform app_private.log('expense.recorded','expense',p_key::text,p_amount);
 return p_key;
end $$;
create function public.admin_dre(p_from timestamptz,p_to timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sales bigint;discounts bigint;returns bigint;cost numeric;expenses bigint;legacy int;missing int;entries jsonb;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<=p_from or p_to-p_from>interval '366 days' then raise exception 'invalid_period'; end if;
 select coalesce(sum(total_cents),0),coalesce(sum(discount_cents),0) into sales,discounts
 from public.orders where paid_at>=p_from and paid_at<p_to;
 select coalesce(sum(p.amount_cents),0) into returns from public.payment_attempts p join public.orders o on o.id=p.order_id
 where o.paid_at>=p_from and o.paid_at<p_to and p.status='refunded';
 select coalesce(sum(-m.quantity*coalesce(m.unit_cost_snapshot_cents,i.unit_cost_cents)),0),count(*) filter(where m.unit_cost_snapshot_cents is null)
 into cost,legacy from public.stock_movements m join public.ingredients i on i.id=m.ingredient_id join public.orders o on o.id=m.order_id
 where o.paid_at>=p_from and o.paid_at<p_to;
 select count(distinct oi.product_id) into missing from public.order_items oi join public.orders o on o.id=oi.order_id
 where o.paid_at>=p_from and o.paid_at<p_to and not exists(select 1 from public.recipe_items r where r.product_id=oi.product_id);
 select coalesce(sum(amount_cents),0) into expenses from public.operating_expenses
 where expense_date>=(p_from at time zone 'America/Recife')::date and expense_date<(p_to at time zone 'America/Recife')::date;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.expense_date desc,e.created_at desc),'[]') into entries
 from public.operating_expenses e where expense_date>=(p_from at time zone 'America/Recife')::date and expense_date<(p_to at time zone 'America/Recife')::date;
 return jsonb_build_object('sales_cents',sales,'discounts_cents',discounts,'refunds_cents',returns,
   'net_revenue_cents',sales-returns,'cost_cents',round(cost),'expense_cents',expenses,
   'result_cents',case when missing>0 then null else sales-returns-round(cost)-expenses end,
   'legacy_cost_entries',legacy,'products_without_recipe',missing,'expenses',entries);
end $$;
revoke all on function app_private.snapshot_ingredient_cost() from public,anon,authenticated,service_role;
revoke all on function public.record_operating_expense(uuid,text,int,date,text),public.admin_dre(timestamptz,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.record_operating_expense(uuid,text,int,date,text),public.admin_dre(timestamptz,timestamptz) to authenticated;

-- SOURCE: supabase/migrations/202611060015_public_menu.sql
-- SHA256: 345f75d012727061cef99bb5dc1eb76bf688c49323b2bb175c0d161b5fff0639
-- Mostruário público: somente produtos ativos e campos de apresentação.
-- Não concede acesso direto às tabelas nem permite criar pedidos ou pagamentos.

create or replace function public.public_menu()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'category', p.category,
    'description', p.description,
    'price_cents', p.price_cents,
    'image_path', p.image_path
  ) order by p.category, p.price_cents, p.name, p.id), '[]'::jsonb)
  from public.products p where p.active = true
$$;
revoke all on function public.public_menu() from public, anon, authenticated;
grant execute on function public.public_menu() to anon, authenticated;
comment on function public.public_menu() is 'Mostruário público somente leitura; exclui custos, estoque, clientes e dados de operação.';

-- SOURCE: supabase/migrations/202611070016_online_orders.sql
-- SHA256: 32fe2d50862e3c4e10aed8a3f15c268b51ad0b9039c84e1a7d3ef29f0f97e1fe
-- Fluxo online independente dos lançamentos do PDV: recebimentos complementares
-- não violam a regra de uma cobrança confirmada por venda do caixa existente.
create table public.online_shop_settings (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default true,
 delivery_enabled boolean not null default false,
 delivery_fee_cents int not null default 0 check(delivery_fee_cents between 0 and 100000),
 cash_enabled boolean not null default true,
 whatsapp_number text not null default '' check(whatsapp_number='' or whatsapp_number ~ '^[0-9]{10,15}$')
);
insert into public.online_shop_settings(singleton) values(true);
create table public.online_orders (
 id uuid primary key default gen_random_uuid(),number bigint generated always as identity unique,
 token_hash text not null unique,idempotency_key uuid not null unique,request_hash text not null,
 status text not null check(status in ('payment_pending','awaiting_store','accepted','preparing','ready','dispatched','completed','cancelled')),
 fulfillment text not null check(fulfillment in ('pickup','delivery')),
 payment_method text not null check(payment_method in ('pix','card','cash')),
 items jsonb not null,subtotal_cents int not null check(subtotal_cents>0),
 delivery_fee_cents int not null check(delivery_fee_cents>=0),total_cents int not null check(total_cents>0),
 paid_cents int not null default 0 check(paid_cents>=0),revision int not null default 1,
 cash_change_for_cents int check(cash_change_for_cents>0),cash_authorized boolean not null default false,
 assigned_to uuid references public.profiles(id),shift_id uuid references public.shifts(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 paid_at timestamptz,check(total_cents=subtotal_cents+delivery_fee_cents)
);
create table app_private.online_contacts (
 order_id uuid primary key references public.online_orders(id),name text not null,phone text not null,
 email text not null,address text not null,whatsapp_consent boolean not null default false
);
create table public.online_changes (
 id uuid primary key,order_id uuid not null references public.online_orders(id),request_hash text not null,
 base_revision int not null,items jsonb not null,total_cents int not null,subtotal_cents int not null,
 reason text not null check(length(reason) between 3 and 500),
 sectors public.sector[] not null,status text not null default 'requested' check(status in ('requested','accepted','rejected')),
 review_reason text,reviewed_by uuid references public.profiles(id),created_at timestamptz not null default now(),reviewed_at timestamptz
);
create unique index online_one_requested_change on public.online_changes(order_id) where status='requested';
create table app_private.online_change_votes(change_id uuid references public.online_changes(id),sector public.sector,actor_id uuid references public.profiles(id),primary key(change_id,sector));
create table public.online_kitchen_jobs (
 order_id uuid references public.online_orders(id),sector public.sector,revision int not null,
 items_snapshot jsonb not null default '[]',status text not null check(status in ('queued','preparing','ready')),updated_at timestamptz not null default now(),primary key(order_id,sector)
);
create table public.online_payments (
 id uuid primary key,order_id uuid not null references public.online_orders(id),revision int not null,
 method text not null check(method in ('pix','card','cash')),amount_cents int not null check(amount_cents>0),
 status text not null default 'pending' check(status in ('pending','confirmed','failed')),
 provider text,provider_reference text unique,checkout_url text,pix_code text,expires_at timestamptz,
 creation_state text not null default 'new' check(creation_state in ('new','creating','ready','uncertain')),
 creation_lease_until timestamptz,created_at timestamptz not null default now(),confirmed_at timestamptz,
 received_by uuid references public.profiles(id),shift_id uuid references public.shifts(id),tendered_cents int
);
create unique index online_one_pending_payment on public.online_payments(order_id) where status='pending';
create table app_private.online_payment_events(provider text,event_id text,payment_id uuid references public.online_payments(id),payload_hash text not null,primary key(provider,event_id));
create table public.online_refunds(id uuid primary key,order_id uuid references public.online_orders(id),amount_cents int not null check(amount_cents>0),bank_reference text not null unique,reason text not null,actor_id uuid references public.profiles(id),created_at timestamptz not null default now());
create table app_private.online_allocations(order_id uuid references public.online_orders(id),ingredient_id uuid references public.ingredients(id),quantity numeric not null,primary key(order_id,ingredient_id));
create table public.online_stock_movements(id bigint generated always as identity primary key,order_id uuid references public.online_orders(id),revision int not null,ingredient_id uuid references public.ingredients(id),quantity numeric not null check(quantity<0),unit_cost_cents numeric not null,created_at timestamptz not null default now(),unique(order_id,revision,ingredient_id));
create table public.online_notifications (
 id uuid primary key default gen_random_uuid(),order_id uuid references public.online_orders(id),topic text not null,revision int not null,
 attempts int not null default 0,next_attempt_at timestamptz not null default now(),lease_until timestamptz,delivered_at timestamptz,last_error text,
 unique(order_id,topic,revision)
);
create table app_private.online_rate_limits(bucket text primary key,window_start timestamptz not null,hits int not null);
create table app_private.online_handoffs(sender text primary key,paused_until timestamptz not null);
create index online_orders_state_time on public.online_orders(status,created_at);
create trigger online_stock_immutable before update or delete or truncate on public.online_stock_movements for each statement execute function app_private.immutable_log();
create trigger online_refunds_immutable before update or delete or truncate on public.online_refunds for each statement execute function app_private.immutable_log();

create function app_private.online_items(p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb;p public.products;qty int;mods text[];result jsonb:='[]';total bigint:=0;
begin
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'invalid_items';end if;
 perform 1 from public.products where id in(select x->>'product_id' from jsonb_array_elements(p_items) x) order by id for share;
 for item in select * from jsonb_array_elements(p_items) loop
  select * into p from public.products where id=item->>'product_id' and active;
  if not found then raise exception 'product_unavailable';end if;
  if coalesce(item->>'quantity','') !~ '^[0-9]{1,3}$' then raise exception 'invalid_quantity';end if;
  qty:=(item->>'quantity')::int;if qty not between 1 and 100 then raise exception 'invalid_quantity';end if;
  if jsonb_typeof(coalesce(item->'modifiers','[]'))<>'array' then raise exception 'invalid_modifier';end if;
  mods:=array(select jsonb_array_elements_text(coalesce(item->'modifiers','[]')));
  if not mods<@p.allowed_modifiers or cardinality(mods)>20 or (select count(*) from unnest(mods) x where x like 'Ponto:%')>1 then raise exception 'invalid_modifier';end if;
  if length(coalesce(item->>'notes',''))>500 then raise exception 'notes_too_long';end if;
  total:=total+p.price_cents::bigint*qty;if total>1000000 then raise exception 'order_too_large';end if;
  result:=result||jsonb_build_array(jsonb_build_object('product_id',p.id,'name',p.name,'quantity',qty,'unit_price_cents',p.price_cents,'sector',p.sector,'modifiers',to_jsonb(mods),'notes',coalesce(item->>'notes','')));
 end loop;
 return jsonb_build_object('items',result,'subtotal_cents',total);
end $$;
create function public.online_shop_config() returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(s) - 'singleton' from public.online_shop_settings s where singleton
$$;
create function public.online_save_settings(p_settings jsonb,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;perform app_private.reason(p_reason);
 update public.online_shop_settings set enabled=(p_settings->>'enabled')::boolean,delivery_enabled=(p_settings->>'delivery_enabled')::boolean,
 delivery_fee_cents=(p_settings->>'delivery_fee_cents')::int,cash_enabled=(p_settings->>'cash_enabled')::boolean,whatsapp_number=coalesce(p_settings->>'whatsapp_number','') where singleton;
 perform app_private.log('online.settings_updated','shop','online');
end $$;
create function public.online_rate_limit(p_bucket text,p_limit int,p_seconds int) returns boolean language plpgsql security definer set search_path='' as $$
declare n int;
begin
 insert into app_private.online_rate_limits values(left(p_bucket,150),now(),1)
 on conflict(bucket) do update set hits=case when online_rate_limits.window_start<now()-make_interval(secs=>p_seconds) then 1 else online_rate_limits.hits+1 end,
 window_start=case when online_rate_limits.window_start<now()-make_interval(secs=>p_seconds) then now() else online_rate_limits.window_start end returning hits into n;
 return n<=p_limit;
end $$;
create function public.online_quote(p_items jsonb,p_fulfillment text) returns jsonb language plpgsql security definer set search_path='' as $$
declare c jsonb;s public.online_shop_settings;fee int;
begin
 select * into s from public.online_shop_settings where singleton;
 if not s.enabled then raise exception 'shop_closed';end if;
 if p_fulfillment not in ('pickup','delivery') or p_fulfillment is null then raise exception 'invalid_fulfillment';end if;
 if p_fulfillment='delivery' and not s.delivery_enabled then raise exception 'delivery_unavailable';end if;
 c:=app_private.online_items(p_items);fee:=case when p_fulfillment='delivery' then s.delivery_fee_cents else 0 end;
 if (c->>'subtotal_cents')::int+fee>1000000 then raise exception 'order_too_large';end if;
 return c||jsonb_build_object('delivery_fee_cents',fee,'total_cents',(c->>'subtotal_cents')::int+fee);
end $$;
create function public.online_create_order(p_key uuid,p_tracking text,p_items jsonb,p_contact jsonb,p_fulfillment text,p_method text,p_change_for int,p_expected_total int) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if p_method is null or p_method not in ('pix','card','cash') or (p_method='cash' and not s.cash_enabled) then raise exception 'payment_unavailable';end if;
 if p_contact is null or length(trim(coalesce(p_contact->>'name',''))) not between 2 and 100 or coalesce(p_contact->>'phone','') !~ '^[0-9]{10,15}$' or length(coalesce(p_contact->>'email',''))>254 or length(coalesce(p_contact->>'address',''))>500 then raise exception 'invalid_contact';end if;
 if coalesce(p_contact->>'email','') !~ '^[^ @]+@[^ @]+\.[^ @]+$' then raise exception 'email_required';end if;
 if p_fulfillment='delivery' and length(trim(coalesce(p_contact->>'address','')))<10 then raise exception 'delivery_contact_required';end if;
 q:=public.online_quote(p_items,p_fulfillment);
 if p_expected_total is null or p_expected_total<>(q->>'total_cents')::int then raise exception 'price_changed_review_order';end if;
 if p_change_for is not null and (p_method<>'cash' or p_change_for<p_expected_total or p_change_for>1000000) then raise exception 'invalid_change_amount';end if;
 insert into public.online_orders(token_hash,idempotency_key,request_hash,status,fulfillment,payment_method,items,subtotal_cents,delivery_fee_cents,total_cents,cash_change_for_cents)
 values(encode(extensions.digest(p_tracking,'sha256'),'hex'),p_key,h,case when p_method='cash' then 'awaiting_store' else 'payment_pending' end,p_fulfillment,p_method,q->'items',(q->>'subtotal_cents')::int,(q->>'delivery_fee_cents')::int,p_expected_total,p_change_for) returning * into o;
 insert into app_private.online_contacts values(o.id,trim(p_contact->>'name'),p_contact->>'phone',coalesce(p_contact->>'email',''),coalesce(p_contact->>'address',''),coalesce((p_contact->>'whatsapp_consent')::boolean,false));
 insert into public.online_notifications(order_id,topic,revision) values(o.id,'order.received',o.revision);
 return jsonb_build_object('id',o.id,'number',o.number,'total_cents',o.total_cents,'status',o.status);
end $$;
create function app_private.online_resolve(p_tracking text) returns public.online_orders language plpgsql stable security definer set search_path='' as $$
declare o public.online_orders;
begin
 if p_tracking is null or p_tracking !~ '^[a-f0-9]{64}$' then raise exception 'order_unavailable' using errcode='42501';end if;
 select * into o from public.online_orders where token_hash=encode(extensions.digest(p_tracking,'sha256'),'hex');
 if not found then raise exception 'order_unavailable' using errcode='42501';end if;return o;
end $$;
create function public.online_order_status(p_tracking text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.online_orders;changes jsonb;payments jsonb;
begin
 o:=app_private.online_resolve(p_tracking);
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'status',c.status,'reason',c.reason,'review_reason',c.review_reason,'total_cents',c.total_cents,'created_at',c.created_at,'sectors',c.sectors,'approved_sectors',(select coalesce(jsonb_agg(v.sector),'[]') from app_private.online_change_votes v where v.change_id=c.id)) order by c.created_at desc),'[]') into changes from public.online_changes c where c.order_id=o.id;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'method',p.method,'provider',p.provider,'status',p.status,'amount_cents',p.amount_cents,'pix_code',p.pix_code,'expires_at',p.expires_at,'checkout_url',p.checkout_url) order by p.created_at desc),'[]') into payments from public.online_payments p where p.order_id=o.id;
 return jsonb_build_object('id',o.id,'number',o.number,'status',o.status,'fulfillment',o.fulfillment,'items',o.items,'revision',o.revision,'subtotal_cents',o.subtotal_cents,'delivery_fee_cents',o.delivery_fee_cents,'total_cents',o.total_cents,'paid_cents',o.paid_cents,'due_cents',greatest(0,o.total_cents-o.paid_cents),'refund_due_cents',greatest(0,o.paid_cents-o.total_cents),'payment_method',o.payment_method,'cash_change_for_cents',o.cash_change_for_cents,'changes',changes,'payments',payments);
end $$;

-- Liberação atômica e baixa real: remoções não devolvem insumos preparados ao estoque.
create function app_private.online_release(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare o public.online_orders;r record;previous numeric;delta numeric;cost numeric;seen uuid[]:='{}';jobsector public.sector;snapshot jsonb;
begin
 select * into o from public.online_orders where id=p_order for update;
 if o.status in ('cancelled','completed','dispatched','ready') then return;end if;
 if o.paid_cents<o.total_cents and not (o.payment_method='cash' and o.cash_authorized) then raise exception 'payment_required';end if;
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
 insert into public.online_notifications(order_id,topic,revision) values(o.id,case when o.paid_cents>=o.total_cents then 'order.paid' else 'order.cash_accepted' end,o.revision) on conflict do nothing;
end $$;

create function public.online_request_change(p_tracking text,p_key uuid,p_items jsonb,p_reason text,p_expected_total int) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.online_orders;q jsonb;c public.online_changes;h text;sectors public.sector[];
begin
 o:=app_private.online_resolve(p_tracking);select * into o from public.online_orders where id=o.id for update;
 h:=encode(extensions.digest(jsonb_build_object('items',p_items,'reason',p_reason,'total',p_expected_total)::text,'sha256'),'hex');
 select * into c from public.online_changes where id=p_key;
 if found then if c.order_id<>o.id or c.request_hash<>h then raise exception 'idempotency_conflict';end if;return c.id;end if;
 if o.status not in ('accepted','preparing') or exists(select 1 from public.online_payments where order_id=o.id and status='pending') then raise exception 'change_not_allowed';end if;
 if length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'change_reason_required';end if;
 q:=app_private.online_items(p_items);q:=q||jsonb_build_object('total_cents',(q->>'subtotal_cents')::int+o.delivery_fee_cents);
 if p_expected_total is null or p_expected_total<>(q->>'total_cents')::int then raise exception 'price_changed_review_order';end if;
 select array_agg(distinct (i->>'sector')::public.sector) into sectors from jsonb_array_elements(o.items||(q->'items')) i;
 insert into public.online_changes(id,order_id,request_hash,base_revision,items,total_cents,subtotal_cents,reason,sectors)
 values(p_key,o.id,h,o.revision,q->'items',p_expected_total,(q->>'subtotal_cents')::int,trim(p_reason),sectors);
 return p_key;
end $$;
create function public.online_review_change(p_change uuid,p_accept boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
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
 update public.online_orders set items=c.items,subtotal_cents=c.subtotal_cents,total_cents=c.total_cents,revision=revision+1,updated_at=now(),
 payment_method=case when paid_cents>0 and c.total_cents>paid_cents then 'pix' else payment_method end,
 status=case when c.total_cents>paid_cents and not(payment_method='cash' and cash_authorized and paid_cents=0) then 'payment_pending' else 'accepted' end where id=o.id;
 if c.total_cents<=o.paid_cents or (o.payment_method='cash' and o.cash_authorized and o.paid_cents=0) then perform app_private.online_release(o.id);end if;
 insert into public.online_notifications(order_id,topic,revision) values(o.id,'change.accepted',o.revision+1) on conflict do nothing;
 perform app_private.reason(p_reason);perform app_private.log('online.change_accepted','online_order',o.id::text,c.total_cents-o.total_cents);
end $$;

create function public.online_prepare_payment(p_tracking text,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.online_orders;p public.online_payments;c app_private.online_contacts;
begin
 o:=app_private.online_resolve(p_tracking);select * into o from public.online_orders where id=o.id for update;
 if o.status<>'payment_pending' or o.payment_method not in ('pix','card') or o.total_cents<=o.paid_cents then raise exception 'payment_not_allowed';end if;
 select * into p from public.online_payments where id=p_key;
 if found and (p.order_id<>o.id or p.revision<>o.revision) then raise exception 'idempotency_conflict';end if;
 select * into p from public.online_payments where order_id=o.id and status='pending';
 if not found then insert into public.online_payments(id,order_id,revision,method,amount_cents) values(p_key,o.id,o.revision,o.payment_method,o.total_cents-o.paid_cents) returning * into p;end if;
 select * into c from app_private.online_contacts where order_id=o.id;
 return jsonb_build_object('id',p.id,'order_id',o.id,'number',o.number,'amount_cents',p.amount_cents,'method',p.method,'status',p.status,'provider_reference',p.provider_reference,'checkout_url',p.checkout_url,'pix_code',p.pix_code,'expires_at',p.expires_at,'email',c.email);
end $$;
create function public.online_record_artifact(p_payment uuid,p_provider text,p_reference text,p_url text,p_pix text,p_expires timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_url is not null and p_url !~ '^https://(www\.|sandbox\.)?(mercadopago\.com\.br|mercadopago\.com)/' then raise exception 'invalid_checkout_url';end if;
 update public.online_payments set provider=p_provider,provider_reference=p_reference,checkout_url=p_url,pix_code=p_pix,expires_at=p_expires,creation_state='ready' where id=p_payment and status='pending' and (provider_reference is null or provider_reference=p_reference);
 if not found then raise exception 'payment_artifact_conflict';end if;
end $$;
create function public.online_confirm_payment(p_payment uuid,p_amount int,p_reference text,p_provider text,p_event text,p_hash text) returns void language plpgsql security definer set search_path='' as $$
declare p public.online_payments;o public.online_orders;previous app_private.online_payment_events;
begin
 select * into p from public.online_payments where id=p_payment for update;
 if not found or p.method='cash' or p.amount_cents<>p_amount or p.status not in ('pending','confirmed') or coalesce(p_reference,'')='' or coalesce(p_event,'')='' then raise exception 'invalid_provider_payment';end if;
 select * into previous from app_private.online_payment_events where provider=p_provider and event_id=p_event;
 if found then if previous.payment_id<>p.id or previous.payload_hash<>p_hash then raise exception 'event_conflict';end if;return;end if;
 if p.status='confirmed' then
  if p.provider_reference<>p_reference then raise exception 'reference_conflict';end if;return;
 end if;
 if p.provider_reference is not null and p.provider_reference<>p_reference then raise exception 'reference_conflict';end if;
 select * into o from public.online_orders where id=p.order_id for update;
 insert into app_private.online_payment_events values(p_provider,p_event,p.id,p_hash);
 update public.online_payments set status='confirmed',provider=p_provider,provider_reference=p_reference,confirmed_at=now() where id=p.id;
 update public.online_orders set paid_cents=paid_cents+p.amount_cents,paid_at=coalesce(paid_at,now()),updated_at=now() where id=o.id;
 if o.status<>'cancelled' and o.revision=p.revision then perform app_private.online_release(o.id);end if;
end $$;

create function public.online_claim_order(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare turn uuid;o public.online_orders;
begin
 if not coalesce(app_private.can_operate(),false) then raise exception 'access_denied' using errcode='42501';end if;
 select id into turn from public.shifts where cashier_id=auth.uid() and closed_at is null for update;if turn is null then raise exception 'open_shift_required';end if;
 select * into o from public.online_orders where id=p_order for update;
 if not found or (o.assigned_to is not null and o.assigned_to<>auth.uid() and not app_private.is_admin()) then raise exception 'order_not_assigned';end if;
 update public.online_orders set assigned_to=auth.uid(),shift_id=turn where id=o.id;
end $$;
create function public.online_accept_cash(p_order uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare o public.online_orders;
begin
 if not coalesce(app_private.can_operate(),false) then raise exception 'access_denied' using errcode='42501';end if;
 select * into o from public.online_orders where id=p_order for update;
 if not found or o.payment_method<>'cash' or o.status not in ('awaiting_store','accepted','preparing') or (o.assigned_to<>auth.uid() and not app_private.is_admin()) or o.assigned_to is null then raise exception 'order_not_assigned';end if;
 perform app_private.reason(p_reason);update public.online_orders set cash_authorized=true where id=o.id;
 perform app_private.online_release(o.id);perform app_private.log('online.cash_authorized','online_order',o.id::text);
end $$;
create function public.online_collect_cash(p_order uuid,p_key uuid,p_tendered int) returns void language plpgsql security definer set search_path='' as $$
declare o public.online_orders;p public.online_payments;turn uuid;due int;
begin
 if not coalesce(app_private.can_operate(),false) then raise exception 'access_denied' using errcode='42501';end if;
 select * into o from public.online_orders where id=p_order for update;
 if not found or not o.cash_authorized or o.payment_method<>'cash' or o.status in ('cancelled','awaiting_store') or (o.assigned_to<>auth.uid() and not app_private.is_admin()) or o.assigned_to is null then raise exception 'cash_confirmation_not_allowed';end if;
 select * into p from public.online_payments where id=p_key;
 if found then if p.order_id<>o.id or p.method<>'cash' or p.tendered_cents<>p_tendered then raise exception 'idempotency_conflict';end if;return;end if;
 select id into turn from public.shifts where cashier_id=auth.uid() and closed_at is null for update;if turn is null then raise exception 'open_shift_required';end if;
 due:=o.total_cents-o.paid_cents;if due<=0 or p_tendered is null or p_tendered<due or p_tendered>1000000 then raise exception 'invalid_cash_received';end if;
 insert into public.online_payments(id,order_id,revision,method,amount_cents,status,confirmed_at,received_by,shift_id,tendered_cents) values(p_key,o.id,o.revision,'cash',due,'confirmed',now(),auth.uid(),turn,p_tendered);
 update public.online_orders set paid_cents=paid_cents+due,paid_at=coalesce(paid_at,now()),updated_at=now() where id=o.id;
 perform app_private.reason('Recebimento físico conferido de pedido online');perform app_private.log('online.cash_received','online_order',o.id::text,due);
end $$;
create function public.online_record_refund(p_order uuid,p_key uuid,p_amount int,p_reference text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare o public.online_orders;r public.online_refunds;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;perform app_private.reason(p_reason);
 select * into o from public.online_orders where id=p_order for update;
 select * into r from public.online_refunds where id=p_key;
 if found then if r.order_id<>o.id or r.amount_cents<>p_amount or r.bank_reference<>p_reference then raise exception 'idempotency_conflict';end if;return;end if;
 if p_amount is null or p_amount<=0 or p_amount>o.paid_cents-o.total_cents or length(trim(coalesce(p_reference,''))) not between 8 and 100 then raise exception 'invalid_refund';end if;
 insert into public.online_refunds values(p_key,o.id,p_amount,trim(p_reference),p_reason,auth.uid(),now());
 update public.online_orders set paid_cents=paid_cents-p_amount where id=o.id;
 perform app_private.log('online.refund_recorded','online_order',o.id::text,p_amount);
end $$;

create function public.online_kitchen_queue() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare mysector public.sector;orders jsonb;changes jsonb;isadmin boolean:=app_private.is_admin();
begin
 if not (isadmin or coalesce(app_private.role()='kitchen' and app_private.terminal_open(),false)) then raise exception 'access_denied' using errcode='42501';end if;
 select sector into mysector from public.profiles where id=auth.uid();
 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'number',o.number,'status',o.status,'fulfillment',o.fulfillment,'revision',o.revision,'sector',j.sector,'job_status',j.status,'change_note',(select reason from public.online_changes where order_id=o.id and status='accepted' order by reviewed_at desc limit 1),'created_at',o.created_at,'items',(select jsonb_agg(i-'unit_price_cents') from jsonb_array_elements(o.items) i where (i->>'sector')::public.sector=j.sector)) order by o.created_at),'[]') into orders from public.online_orders o join public.online_kitchen_jobs j on j.order_id=o.id and j.revision=o.revision where o.status in ('accepted','preparing') and j.status<>'ready' and (isadmin or j.sector=mysector);
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'number',o.number,'reason',c.reason,'created_at',c.created_at,'sectors',c.sectors,'approved_sectors',(select coalesce(jsonb_agg(v.sector),'[]') from app_private.online_change_votes v where v.change_id=c.id),'items',(select jsonb_agg(i-'unit_price_cents') from jsonb_array_elements(c.items) i where isadmin or (i->>'sector')::public.sector=mysector)) order by c.created_at),'[]') into changes from public.online_changes c join public.online_orders o on o.id=c.order_id where c.status='requested' and (isadmin or mysector=any(c.sectors));
 return jsonb_build_object('orders',orders,'changes',changes);
end $$;
create function public.online_kitchen_work(p_order uuid,p_sector public.sector,p_revision int,p_next text) returns void language plpgsql security definer set search_path='' as $$
declare o public.online_orders;j public.online_kitchen_jobs;
begin
 if not (app_private.is_admin() or coalesce(app_private.role()='kitchen' and app_private.terminal_open() and (select sector from public.profiles where id=auth.uid())=p_sector,false)) then raise exception 'access_denied' using errcode='42501';end if;
 select * into o from public.online_orders where id=p_order for update;
 select * into j from public.online_kitchen_jobs where order_id=p_order and sector=p_sector for update;
 if not found or o.revision<>p_revision or j.revision<>p_revision or o.status not in ('accepted','preparing') then raise exception 'order_changed_refresh';end if;
 if exists(select 1 from public.online_changes where order_id=o.id and status='requested') then raise exception 'review_change_first';end if;
 if j.status=p_next then return;end if;
 if not ((j.status='queued' and p_next='preparing') or (j.status='preparing' and p_next='ready')) then raise exception 'invalid_transition';end if;
 update public.online_kitchen_jobs set status=p_next,updated_at=now() where order_id=p_order and sector=p_sector;
 update public.online_orders set status=case when not exists(select 1 from public.online_kitchen_jobs where order_id=o.id and status<>'ready') then 'ready' else 'preparing' end,updated_at=now() where id=o.id;
 insert into public.online_notifications(order_id,topic,revision) select o.id,'order.ready',o.revision where not exists(select 1 from public.online_kitchen_jobs where order_id=o.id and status<>'ready') on conflict do nothing;
end $$;
create function public.online_operations_queue() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not coalesce(app_private.can_operate(),false) then raise exception 'access_denied' using errcode='42501';end if;
 select coalesce(jsonb_agg((to_jsonb(o)-'token_hash'-'request_hash'-'idempotency_key')||jsonb_build_object('payments',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'provider',p.provider,'method',p.method,'status',p.status,'amount_cents',p.amount_cents,'created_at',p.created_at) order by p.created_at desc),'[]') from public.online_payments p where p.order_id=o.id),'contact',case when app_private.is_admin() or o.assigned_to=auth.uid() then (select to_jsonb(c)-'order_id' from app_private.online_contacts c where c.order_id=o.id) else null end,'due_cents',greatest(0,o.total_cents-o.paid_cents),'refund_due_cents',greatest(0,o.paid_cents-o.total_cents)) order by o.created_at desc),'[]') into result from public.online_orders o where o.created_at>now()-interval '7 days' and (o.assigned_to is null or o.assigned_to=auth.uid() or app_private.is_admin());
 return result;
end $$;
create function public.online_fulfill(p_order uuid,p_next text) returns void language plpgsql security definer set search_path='' as $$
declare o public.online_orders;
begin
 if not coalesce(app_private.can_operate(),false) then raise exception 'access_denied' using errcode='42501';end if;
 select * into o from public.online_orders where id=p_order for update;
 if not found or (o.assigned_to<>auth.uid() and not app_private.is_admin()) or o.assigned_to is null then raise exception 'order_not_assigned';end if;
 if o.status=p_next then return;end if;
 if not ((o.status='ready' and p_next='dispatched' and o.fulfillment='delivery') or (o.status in ('ready','dispatched') and p_next='completed' and o.paid_cents>=o.total_cents)) then raise exception 'delivery_or_payment_not_ready';end if;
 update public.online_orders set status=p_next,updated_at=now() where id=o.id;
 insert into public.online_notifications(order_id,topic,revision) values(o.id,'order.'||p_next,o.revision) on conflict do nothing;
end $$;

-- Privilégios por função explícitos: revogar defaults por schema não remove
-- o EXECUTE global padrão do PostgreSQL para funções recém-criadas.
do $priv$ declare f regprocedure;begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'online\_%' escape '\' loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f);
 end loop;
end $priv$;
-- Nenhuma tabela online pode ser lida ou alterada diretamente por visitantes.
alter table public.online_shop_settings enable row level security;
alter table public.online_orders enable row level security;
alter table public.online_changes enable row level security;
alter table public.online_kitchen_jobs enable row level security;
alter table public.online_payments enable row level security;
alter table public.online_refunds enable row level security;
alter table public.online_stock_movements enable row level security;
alter table public.online_notifications enable row level security;
revoke all on public.online_shop_settings,public.online_orders,public.online_changes,public.online_kitchen_jobs,public.online_payments,public.online_refunds,public.online_stock_movements,public.online_notifications from public,anon,authenticated;
revoke all on function app_private.online_items(jsonb),app_private.online_resolve(text),app_private.online_release(uuid) from public,anon,authenticated;
grant execute on function public.online_shop_config() to anon,authenticated;
grant execute on function public.online_save_settings(jsonb,text),public.online_claim_order(uuid),public.online_accept_cash(uuid,text),public.online_collect_cash(uuid,uuid,int),public.online_record_refund(uuid,uuid,int,text,text),public.online_kitchen_queue(),public.online_review_change(uuid,boolean,text),public.online_kitchen_work(uuid,public.sector,int,text),public.online_operations_queue(),public.online_fulfill(uuid,text) to authenticated;
grant execute on function public.online_shop_config(),public.online_rate_limit(text,int,int),public.online_quote(jsonb,text),public.online_create_order(uuid,text,jsonb,jsonb,text,text,int,int),public.online_order_status(text),public.online_request_change(text,uuid,jsonb,text,int),public.online_prepare_payment(text,uuid),public.online_record_artifact(uuid,text,text,text,text,timestamptz),public.online_confirm_payment(uuid,int,text,text,text,text) to service_role;

-- SOURCE: supabase/migrations/202611070017_online_integrations.sql
-- SHA256: 39489a7a8c9d2675a00db152913463d0db949a06f311daa20a1f011fe935fc16
create function app_private.online_payment(p_order uuid,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.online_orders;p public.online_payments;c app_private.online_contacts;
begin
 select * into o from public.online_orders where id=p_order for update;
 if not found or o.status<>'payment_pending' or o.payment_method not in ('pix','card') or o.total_cents<=o.paid_cents then raise exception 'payment_not_allowed';end if;
 select * into p from public.online_payments where id=p_key;
 if found and (p.order_id<>o.id or p.revision<>o.revision) then raise exception 'idempotency_conflict';end if;
 select * into p from public.online_payments where order_id=o.id and status='pending';
 if not found then insert into public.online_payments(id,order_id,revision,method,amount_cents) values(p_key,o.id,o.revision,o.payment_method,o.total_cents-o.paid_cents) returning * into p;end if;
 select * into c from app_private.online_contacts where order_id=o.id;
 return jsonb_build_object('id',p.id,'order_id',o.id,'number',o.number,'amount_cents',p.amount_cents,'method',p.method,'status',p.status,'creation_state',p.creation_state,'provider_reference',p.provider_reference,'checkout_url',p.checkout_url,'pix_code',p.pix_code,'expires_at',p.expires_at,'email',c.email);
end $$;
create or replace function public.online_prepare_payment(p_tracking text,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.online_orders;
begin o:=app_private.online_resolve(p_tracking);return app_private.online_payment(o.id,p_key);end $$;
create function public.online_claim_payment_creation(p_payment uuid) returns text language plpgsql security definer set search_path='' as $$
declare p public.online_payments;
begin
 select * into p from public.online_payments where id=p_payment and status='pending' for update;
 if not found then raise exception 'payment_not_allowed';end if;
 if p.creation_state='ready' then return 'ready';end if;
 if p.creation_state='creating' and p.creation_lease_until>now() then return 'busy';end if;
 update public.online_payments set creation_state='creating',creation_lease_until=now()+interval '1 minute' where id=p.id;
 return case when p.creation_state='new' then 'new' else 'recover' end;
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_claim_payment_creation' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
create function public.online_uncertain_payment(p_payment uuid) returns void language sql security definer set search_path='' as $$
 update public.online_payments set creation_state='uncertain',creation_lease_until=null where id=p_payment and creation_state='creating'
$$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_uncertain_payment' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;

-- A referência bancária não pode conciliar simultaneamente uma venda PDV e uma online.
create table app_private.manual_bank_references(reference text primary key,payment_identity text not null unique);
insert into app_private.manual_bank_references select provider_reference,'pos:'||id::text from public.payment_attempts where status='confirmed' and provider_reference like 'manual-pix:%';
create function app_private.unique_manual_bank_reference() returns trigger language plpgsql security definer set search_path='' as $$
declare ident text;existing text;
begin
 if new.status::text='confirmed' and new.provider_reference like 'manual-pix:%' then
  ident:=case when tg_table_name='online_payments' then 'online:' else 'pos:' end||new.id::text;
  insert into app_private.manual_bank_references values(new.provider_reference,ident) on conflict(reference) do nothing;
  select payment_identity into existing from app_private.manual_bank_references where reference=new.provider_reference;
  if existing<>ident then raise exception 'bank_reference_already_used' using errcode='23505';end if;
 end if;return new;
end $$;
create trigger online_bank_reference before insert or update on public.online_payments for each row execute function app_private.unique_manual_bank_reference();
create trigger pos_bank_reference before insert or update on public.payment_attempts for each row execute function app_private.unique_manual_bank_reference();
create function public.online_confirm_manual_pix(p_payment uuid,p_reference text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare p public.online_payments;ref text:=upper(regexp_replace(coalesce(p_reference,''),'\s+','','g'));
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;perform app_private.reason(p_reason);
 select * into p from public.online_payments where id=p_payment for update;
 if not found or p.method<>'pix' or p.provider<>'manual_pix' or p.pix_code is null or ref !~ '^[A-Z0-9._:-]{8,100}$' then raise exception 'manual_pix_not_allowed';end if;
 perform public.online_confirm_payment(p.id,p.amount_cents,'manual-pix:'||ref,'manual_pix','manual:'||p.id::text,encode(extensions.digest(ref,'sha256'),'hex'));
 perform app_private.log('online.manual_pix_confirmed','online_order',p.order_id::text,p.amount_cents);
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_confirm_manual_pix' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;

create or replace function public.cash_summary(p_shift uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare turn public.shifts;paid bigint;movements bigint;online_paid bigint;
begin
 if not coalesce(app_private.can_operate(),false) then raise exception 'access_denied' using errcode='42501';end if;
 select * into turn from public.shifts where id=p_shift and (cashier_id=auth.uid() or app_private.is_admin());if not found then raise exception 'shift_unavailable';end if;
 select coalesce(sum(p.amount_cents),0) into paid from public.payment_attempts p join public.orders o on o.id=p.order_id where o.shift_id=p_shift and p.method='cash' and p.status in ('confirmed','refunded');
 select coalesce(sum(p.amount_cents),0) into online_paid from public.online_payments p where p.shift_id=p_shift and p.method='cash' and p.status='confirmed';
 select coalesce(sum(case when kind='supply' then amount_cents else -amount_cents end),0) into movements from public.cash_movements where shift_id=p_shift;
 return jsonb_build_object('opening_cents',turn.opening_cents,'cash_sales_cents',paid+online_paid,'online_cash_sales_cents',online_paid,'movements_cents',movements,'expected_cents',turn.opening_cents+paid+online_paid+movements,'counted_cents',turn.closing_counted_cents,'closed_at',turn.closed_at);
end $$;
create function public.online_admin_metrics() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 return jsonb_build_object('received_cents',(select coalesce(sum(amount_cents),0) from public.online_payments where status='confirmed'),'refunded_cents',(select coalesce(sum(amount_cents),0) from public.online_refunds),'receivable_cents',(select coalesce(sum(greatest(0,total_cents-paid_cents)),0) from public.online_orders where status not in ('cancelled','awaiting_store')),'refund_due_cents',(select coalesce(sum(greatest(0,paid_cents-total_cents)),0) from public.online_orders),'stock_cost_cents',(select coalesce(round(sum(-quantity*unit_cost_cents)),0) from public.online_stock_movements));
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_admin_metrics' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;

create function public.online_claim_notifications() returns jsonb language plpgsql security definer set search_path='' as $$
declare job record;result jsonb:='[]';payment jsonb;
begin
 update public.online_notifications n set delivered_at=now(),last_error='superseded' from public.online_orders o where o.id=n.order_id and n.revision<o.revision and n.delivered_at is null;
 for job in
  with picked as(select n.id from public.online_notifications n join app_private.online_contacts c on c.order_id=n.order_id where n.delivered_at is null and n.attempts<8 and n.next_attempt_at<=now() and (n.lease_until is null or n.lease_until<now()) and c.whatsapp_consent order by n.next_attempt_at for update of n skip locked limit 2),claimed as(update public.online_notifications set lease_until=now()+interval '2 minutes',attempts=attempts+1 where id in(select id from picked) returning *)
  select n.*,o.number,o.status,o.payment_method,greatest(0,o.total_cents-o.paid_cents) due_cents,c.phone from claimed n join public.online_orders o on o.id=n.order_id join app_private.online_contacts c on c.order_id=n.order_id
 loop
  payment:=null;
  if job.topic='change.accepted' and job.due_cents>0 and job.status='payment_pending' and job.payment_method='pix' then payment:=app_private.online_payment(job.order_id,job.id);end if;
  result:=result||jsonb_build_array(jsonb_build_object('id',job.id,'topic',job.topic,'number',job.number,'due_cents',job.due_cents,'phone',job.phone,'payment',payment,'within_window',exists(select 1 from public.whatsapp_inbox i where i.sender=job.phone and i.received_at>now()-interval '23 hours')));
 end loop;return result;
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_claim_notifications' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
create function public.online_finish_notification(p_id uuid,p_success boolean,p_error text default null) returns void language sql security definer set search_path='' as $$
 update public.online_notifications set delivered_at=case when p_success then now() else null end,lease_until=null,next_attempt_at=now()+make_interval(secs=>least(3600,30*power(2,least(attempts,7))::int)),last_error=case when p_success then null else left(p_error,80) end where id=p_id and lease_until is not null
$$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_finish_notification' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
create function public.online_assistant_catalog() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('settings',public.online_shop_config(),'products',coalesce(jsonb_agg(jsonb_build_object('product_id',p.id,'name',p.name,'description',p.description,'category',p.category,'image_path',p.image_path,'price_cents',p.price_cents,'allowed_modifiers',p.allowed_modifiers) order by p.category,p.name),'[]')) from public.products p where p.active
$$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_assistant_catalog' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
create function public.online_automation_allowed(p_sender text,p_handoff boolean default false) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_handoff then
  insert into app_private.online_handoffs values(p_sender,now()+interval '24 hours') on conflict(sender) do update set paused_until=excluded.paused_until;
  return false;
 end if;
 return not exists(select 1 from app_private.online_handoffs where sender=p_sender and paused_until>now()) and not exists(select 1 from public.whatsapp_inbox where sender=p_sender and assigned_to is not null and closed_at is null);
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_automation_allowed' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
create function public.online_resume_automation(p_sender text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;perform app_private.reason(p_reason);
 delete from app_private.online_handoffs where sender=p_sender;
 perform app_private.log('online.automation_resumed','conversation',encode(extensions.digest(p_sender,'sha256'),'hex'));
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_resume_automation' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
revoke all on function app_private.online_payment(uuid,uuid),app_private.unique_manual_bank_reference() from public,anon,authenticated;
grant execute on function public.online_claim_payment_creation(uuid),public.online_uncertain_payment(uuid),public.online_claim_notifications(),public.online_finish_notification(uuid,boolean,text),public.online_assistant_catalog(),public.online_automation_allowed(text,boolean) to service_role;
grant execute on function public.online_confirm_manual_pix(uuid,text,text),public.online_admin_metrics(),public.online_resume_automation(text,text) to authenticated;
create function public.online_change_quote(p_tracking text,p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.online_orders;q jsonb;
begin
 o:=app_private.online_resolve(p_tracking);q:=app_private.online_items(p_items);
 return q||jsonb_build_object('delivery_fee_cents',o.delivery_fee_cents,'total_cents',(q->>'subtotal_cents')::int+o.delivery_fee_cents);
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_change_quote' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
grant execute on function public.online_change_quote(text,jsonb) to service_role;
create function public.online_assistant_history(p_sender text) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('role','user','content',t.body) order by t.received_at),'[]') from(select body,received_at from public.whatsapp_inbox where sender=p_sender and received_at>now()-interval '23 hours' order by received_at desc limit 6) t
$$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_assistant_history' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
grant execute on function public.online_assistant_history(text) to service_role;
-- Abertura/fechamento e recebimento compartilham o lock do turno.
create or replace function public.close_shift(p_shift uuid,p_counted_cents int,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform app_private.reason(p_reason);
 perform 1 from public.shifts where id=p_shift for update;
 if exists(select 1 from public.online_orders where shift_id=p_shift and status not in ('completed','cancelled') and total_cents>paid_cents) then raise exception 'pending_orders_in_shift';end if;
 perform public.close_shift(p_shift,p_counted_cents);
end $$;
create table app_private.online_ai_permissions(sender text primary key,granted_at timestamptz not null,expires_at timestamptz not null);
create function public.online_ai_consent(p_sender text,p_message text) returns text language plpgsql security definer set search_path='' as $$
declare m text:=upper(trim(p_message));
begin
 if m in ('SEM IA','REVOGO IA','NAO AUTORIZO','NÃO AUTORIZO','HUMANO','ATENDENTE') then delete from app_private.online_ai_permissions where sender=p_sender;return 'revoked';end if;
 if m='AUTORIZO IA' then insert into app_private.online_ai_permissions values(p_sender,now(),now()+interval '30 days') on conflict(sender) do update set granted_at=excluded.granted_at,expires_at=excluded.expires_at;return 'granted';end if;
 if exists(select 1 from app_private.online_ai_permissions where sender=p_sender and expires_at>now()) then return 'granted';end if;return 'required';
end $$;
revoke all on function public.online_ai_consent(text,text) from public,anon,authenticated;
grant execute on function public.online_ai_consent(text,text) to service_role;
-- Uma chamada de IA pode demorar: um atendimento por lease, em ordem,
-- impede que a próxima mensagem do mesmo cliente corra em paralelo.
create or replace function public.claim_message_replies() returns jsonb language plpgsql security definer set search_path='' as $$
declare jobs jsonb;
begin
 perform pg_advisory_xact_lock(hashtextextended('online:ai-reply-claim',1));
 with pending as(
  select r.id from app_private.message_replies r join public.whatsapp_inbox i on i.id=r.inbox_id
  where r.state in ('pending','retry','running') and r.attempts<8 and r.next_attempt_at<=now() and (r.lease_until is null or r.lease_until<now())
  and not exists(select 1 from app_private.message_replies active join public.whatsapp_inbox other on other.id=active.inbox_id where active.id<>r.id and active.state='running' and active.lease_until>now() and other.sender=i.sender)
  order by i.received_at for update of r skip locked limit 1
 ),claimed as(update app_private.message_replies set state='running',lease_until=now()+interval '3 minutes',attempts=attempts+1 where id in(select id from pending) returning *)
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'sender',i.sender,'body',i.body,'received_at',i.received_at)),'[]') into jobs from claimed c join public.whatsapp_inbox i on i.id=c.inbox_id;
 return jobs;
end $$;
-- RPCs de serviço usadas pelo fluxo legado também precisam de revogação
-- explícita de PUBLIC; os grants de anon do checkout legado são preservados.
revoke all on function public.confirm_provider_payment(uuid,int,text,text,text,text),public.confirm_provider_refund(uuid,text,int),public.prepare_checkout_payment(text,uuid),public.record_pix_artifact(uuid,text,timestamptz),public.ingest_whatsapp(text,text,text,timestamptz),public.claim_notifications(int),public.finish_notification(uuid,boolean,text),public.claim_message_replies(),public.finish_message_reply(uuid,boolean),public.authenticate_staff_pin(text,text),public.bind_fastpass_session(uuid,text,text) from public,anon,authenticated;

-- SOURCE: supabase/migrations/202611070018_admin_control.sql
-- SHA256: f7ef1da65c5e11888975d8cafd4d5bfba3c64d237c0a8acba9e7d4cd5ba4637e
-- Imagens públicas somente de produtos; os demais buckets não são alterados.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('planeta-product-images','planeta-product-images',true,5242880,array['image/webp']) on conflict(id) do nothing;
do $$begin
 if not exists(select 1 from storage.buckets where id='planeta-product-images' and public and file_size_limit<=5242880 and allowed_mime_types=array['image/webp']) then raise exception 'product_bucket_configuration_conflict';end if;
end $$;
create policy product_image_admin_read on storage.objects for select to authenticated using(bucket_id='planeta-product-images' and app_private.is_admin());
create policy product_image_admin_upload on storage.objects for insert to authenticated with check(bucket_id='planeta-product-images' and app_private.is_admin() and name ~ '^[a-f0-9-]{36}\.webp$');
-- URLs são imutáveis: trocar foto cria outro objeto. Não há UPDATE/upsert.
create policy product_image_admin_cleanup on storage.objects for delete to authenticated using(bucket_id='planeta-product-images' and app_private.is_admin() and not exists(select 1 from public.products p where p.image_path='/storage/v1/object/public/planeta-product-images/'||storage.objects.name));

create or replace function public.save_product(p_product jsonb,p_reason text) returns text language plpgsql security definer set search_path='' as $$
declare ident text:=coalesce(nullif(p_product->>'id',''),gen_random_uuid()::text);category text:=p_product->>'category';mods text[];image text;previous public.products;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if category is null or category not in ('hamburgueres','dogoes','combos','porcoes','pasteis','coxinhas','bebidas','adicionais') or length(trim(coalesce(p_product->>'name',''))) not between 2 and 120 or coalesce(p_product->>'price_cents','') !~ '^[0-9]{1,7}$' or (p_product->>'price_cents')::int not between 1 and 1000000 or coalesce(p_product->>'sector','') not in ('grill','fryer','bar') then raise exception 'invalid_product';end if;
 if jsonb_typeof(coalesce(p_product->'allowed_modifiers','[]'))<>'array' then raise exception 'invalid_modifiers';end if;
 mods:=array(select distinct trim(value) from jsonb_array_elements_text(coalesce(p_product->'allowed_modifiers','[]')));
 if cardinality(mods)>20 or exists(select 1 from unnest(mods) m where length(m) not between 1 and 80) then raise exception 'invalid_modifiers';end if;
 select * into previous from public.products where id=ident for update;
 if p_product ? 'image_path' then image:=nullif(p_product->>'image_path','');
 elsif previous.image_path not like '/menu/%' then image:=previous.image_path;end if;
 image:=coalesce(image,'/menu/'||case when category='combos' then 'hamburgueres' else category end||'.svg');
 if image !~ '^/menu/(hamburgueres|dogoes|porcoes|pasteis|coxinhas|bebidas|adicionais)\.svg$' then
  if image !~ '^/storage/v1/object/public/planeta-product-images/[a-f0-9-]{36}\.webp$' or not exists(select 1 from storage.objects where bucket_id='planeta-product-images' and name=substring(image from '[a-f0-9-]{36}\.webp$')) then raise exception 'invalid_product_image';end if;
 end if;
 insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers,active)
 values(ident,trim(p_product->>'name'),category,left(coalesce(p_product->>'description',''),1000),(p_product->>'price_cents')::int,(p_product->>'sector')::public.sector,image,mods,coalesce((p_product->>'active')::boolean,true))
 on conflict(id) do update set name=excluded.name,category=excluded.category,description=excluded.description,price_cents=excluded.price_cents,sector=excluded.sector,image_path=excluded.image_path,allowed_modifiers=excluded.allowed_modifiers,active=excluded.active;
 return ident;
end $$;

-- Mudança de função/ativação e PIN se confirmam juntos, sem acesso parcial.
create function public.admin_save_staff_access(p_user uuid,p_role public.app_role,p_sector public.sector,p_active boolean,p_pin text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 if p_role is null or p_active is null or (p_role='kitchen' and p_sector is null) or (coalesce(p_pin,'')<>'' and (p_pin !~ '^[0-9]{4}$' or not p_active or p_role='admin')) then raise exception 'invalid_staff_access';end if;
 perform pg_advisory_xact_lock(638194501);
 if coalesce(p_pin,'')<>'' then delete from app_private.pin_credentials where user_id=p_user;end if;
 perform public.manage_staff(p_user,p_role,case when p_role='kitchen' then p_sector else null end,p_active,p_reason);
 if coalesce(p_pin,'')<>'' then perform public.set_staff_pin(p_user,p_pin);end if;
 if p_active and p_role in ('cashier','kitchen') and not exists(select 1 from app_private.pin_credentials where user_id=p_user) then raise exception 'staff_pin_required';end if;
end $$;

-- Custos por grama/ml preservam frações de centavo nas próximas baixas.
alter table public.stock_movements alter column unit_cost_snapshot_cents type numeric(12,4);
-- Cobertura de custos capturada no preparo, sem inventar fichas para vendas antigas.
create table app_private.admin_cost_coverage(origin text check(origin in ('pos','online')),order_id uuid,revision int,complete boolean not null,created_at timestamptz not null default now(),primary key(origin,order_id,revision));
create function app_private.capture_cost_coverage() returns trigger language plpgsql security definer set search_path='' as $$
declare complete boolean;
begin
 if tg_table_name='orders' and old.paid_at is null and new.paid_at is not null then
  select not exists(select 1 from public.order_items i where i.order_id=new.id and not exists(select 1 from public.recipe_items r where r.product_id=i.product_id)) into complete;
  insert into app_private.admin_cost_coverage values('pos',new.id,1,complete,now()) on conflict do nothing;
 elsif tg_table_name='online_orders' then
  if new.status in ('accepted','preparing','ready') and (old.status in ('awaiting_store','payment_pending') or new.revision<>old.revision) then
   select not exists(select 1 from jsonb_array_elements(new.items) i where not exists(select 1 from public.recipe_items r where r.product_id=i->>'product_id')) into complete;
   insert into app_private.admin_cost_coverage values('online',new.id,new.revision,complete,now()) on conflict do nothing;
  end if;
 end if;return new;
end $$;
create trigger pos_cost_coverage after update on public.orders for each row execute function app_private.capture_cost_coverage();
create trigger online_cost_coverage after update on public.online_orders for each row execute function app_private.capture_cost_coverage();
create view app_private.admin_money_movements as
 select confirmed_at at_time,'pos'::text origin,order_id,1 revision,'received'::text kind,amount_cents::numeric amount from public.payment_attempts where status in ('confirmed','refunded') and confirmed_at is not null
 union all select confirmed_at,'pos',order_id,1,'refunded',amount_cents from public.refunds where state='confirmed' and confirmed_at is not null
 union all select confirmed_at,'online',order_id,revision,'received',amount_cents from public.online_payments where status='confirmed'
 union all select created_at,'online',order_id,null,'refunded',amount_cents from public.online_refunds
 union all select created_at,'pos',order_id,1,'cost',greatest(-quantity,0)*coalesce(unit_cost_snapshot_cents,0) from public.stock_movements
 union all select created_at,'online',order_id,revision,'cost',-quantity*unit_cost_cents from public.online_stock_movements
 union all select expense_date::timestamp at time zone 'America/Recife','expense',null,null,'expense',amount_cents from public.operating_expenses;
create function app_private.admin_result_period(p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare start_at timestamptz:=p_from::timestamp at time zone 'America/Recife';end_at timestamptz:=p_to::timestamp at time zone 'America/Recife';received numeric;refunded numeric;cost numeric;expenses numeric;pos numeric;online numeric;orders int;unknown int;
begin
 select coalesce(sum(amount) filter(where kind='received'),0),coalesce(sum(amount) filter(where kind='refunded'),0),coalesce(sum(amount) filter(where kind='cost'),0),coalesce(sum(amount) filter(where kind='expense'),0),coalesce(sum(amount) filter(where kind='received' and origin='pos'),0),coalesce(sum(amount) filter(where kind='received' and origin='online'),0),count(distinct (origin,order_id)) filter(where kind='received') into received,refunded,cost,expenses,pos,online,orders from app_private.admin_money_movements where at_time>=start_at and at_time<end_at;
 select count(*) into unknown from(
  select distinct m.origin,m.order_id,m.revision from app_private.admin_money_movements m left join app_private.admin_cost_coverage c on c.origin=m.origin and c.order_id=m.order_id and c.revision=m.revision where m.kind='received' and m.at_time>=start_at and m.at_time<end_at and c.complete is distinct from true
  union select origin,order_id,revision from app_private.admin_cost_coverage where created_at>=start_at and created_at<end_at and not complete
  union select 'pos',order_id,1 from public.stock_movements where created_at>=start_at and created_at<end_at and unit_cost_snapshot_cents is null
 ) missing;
 return jsonb_build_object('from',p_from,'to',p_to-1,'received_cents',round(received),'refunds_cents',round(refunded),'net_received_cents',round(received-refunded),'cost_cents',round(cost),'expenses_cents',round(expenses),'result_cents',case when unknown=0 then round(received-refunded-cost-expenses) else null end,'incomplete_cost_orders',unknown,'paid_orders',orders,'pos_received_cents',round(pos),'online_received_cents',round(online));
end $$;
create function public.admin_control_snapshot(p_reference date default (now() at time zone 'America/Recife')::date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare periods jsonb;inventory jsonb;trend jsonb;today date:=(now() at time zone 'America/Recife')::date;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 if p_reference is null or p_reference>today or p_reference<today-interval '5 years' then raise exception 'invalid_period';end if;
 periods:=jsonb_build_object('day',app_private.admin_result_period(p_reference,p_reference+1),'week',app_private.admin_result_period(date_trunc('week',p_reference::timestamp)::date,p_reference+1),'month',app_private.admin_result_period(date_trunc('month',p_reference::timestamp)::date,p_reference+1));
 select jsonb_build_object('count',count(*),'low_count',count(*) filter(where stock<=minimum_stock),'negative_count',count(*) filter(where stock<0),'value_cents',coalesce(round(sum(greatest(stock,0)*unit_cost_cents)),0),'items',coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'unit',unit,'stock',stock,'minimum_stock',minimum_stock,'unit_cost_cents',unit_cost_cents) order by (stock<0) desc,(stock<=minimum_stock) desc,name),'[]')) into inventory from public.ingredients;
 select coalesce(jsonb_agg(jsonb_build_object('date',d.day::date,'received_cents',coalesce(m.received,0),'refunds_cents',coalesce(m.refunded,0)) order by d.day),'[]') into trend from generate_series(date_trunc('month',p_reference::timestamp),p_reference::timestamp,interval '1 day') d(day) left join lateral(select sum(amount) filter(where kind='received') received,sum(amount) filter(where kind='refunded') refunded from app_private.admin_money_movements where at_time>=d.day at time zone 'America/Recife' and at_time<(d.day+interval '1 day') at time zone 'America/Recife') m on true;
 return jsonb_build_object('reference_date',p_reference,'timezone','America/Recife','periods',periods,'inventory',inventory,'daily',trend,'open_shifts',(select count(*) from public.shifts where closed_at is null),'receivable_cents',(select coalesce(sum(greatest(total_cents-paid_cents,0)),0) from public.online_orders where status in ('accepted','preparing','ready','dispatched')));
end $$;
create index if not exists pos_receipt_date on public.payment_attempts(confirmed_at) where status in ('confirmed','refunded');
create index if not exists online_receipt_date on public.online_payments(confirmed_at) where status='confirmed';
revoke all on function public.save_product(jsonb,text),public.admin_save_staff_access(uuid,public.app_role,public.sector,boolean,text,text),public.admin_control_snapshot(date) from public,anon,authenticated,service_role;
grant execute on function public.save_product(jsonb,text),public.admin_save_staff_access(uuid,public.app_role,public.sector,boolean,text,text),public.admin_control_snapshot(date) to authenticated;
revoke all on app_private.admin_cost_coverage,app_private.admin_money_movements from public,anon,authenticated,service_role;
revoke all on function app_private.capture_cost_coverage(),app_private.admin_result_period(date,date) from public,anon,authenticated,service_role;

-- SOURCE: supabase/migrations/20261108150436_delivery_checkout.sql
-- SHA256: 93a33babab74acb170e59e861f925100e2f4c774b2f334620664e678cdfe5f0a
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

-- SOURCE: supabase/migrations/20261110122940_menu_customizations.sql
-- SHA256: d875977effadcdf14d2cd312629ffc9ec7d10915910bd8b3330af206357bcf5c
select app_private.reason('Atualizacao das personalizacoes do cardapio: carnes industriais, pasteis, adicionais e sabores diarios.');
-- Disponibilidade de sabores compartilhada por todas as porções, sem alterar preços.
alter table public.online_shop_settings add column coxinha_flavors text[] not null default array['Frango','Presunto'] check(cardinality(coxinha_flavors)<=6);

create function app_private.menu_product_options() returns trigger language plpgsql security definer set search_path='' as $$
declare flavors text[];
begin
 new.allowed_modifiers:=array(select m from unnest(new.allowed_modifiers) m where m not like 'Ponto:%');
 if new.category in ('hamburgueres','dogoes') or new.id='extra-carne' then
  if position('industrializad' in lower(new.description))=0 then new.description:=left(new.description,900)||' Carnes industrializadas; sem escolha de ponto.';end if;
 end if;
 if new.category='pasteis' then new.allowed_modifiers:=array['Com tomate','Com milho','Com batata palha','Com ketchup','Com maionese','Sem acompanhamentos'];end if;
 if new.category='coxinhas' then
  select coxinha_flavors into flavors from public.online_shop_settings where singleton;
  new.allowed_modifiers:=array(select 'Sabor: '||flavor from unnest(flavors) flavor);
  if cardinality(flavors)>1 then new.allowed_modifiers:=array_append(new.allowed_modifiers,'Sabor: Mistas');end if;
 end if;
 return new;
end $$;
revoke all on function app_private.menu_product_options() from public,anon,authenticated;
create trigger menu_product_options before insert or update on public.products for each row execute function app_private.menu_product_options();
-- Preserva imagens, preços, disponibilidade individual e descrições próprias.
update public.products set allowed_modifiers=allowed_modifiers where category in ('hamburgueres','dogoes','pasteis','coxinhas') or id='extra-carne' or exists(select 1 from unnest(allowed_modifiers) m where m like 'Ponto:%');

create function public.online_set_coxinha_flavors(p_flavors text[],p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare flavors text[];
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if p_flavors is null or cardinality(p_flavors)>6 or array_position(p_flavors,null) is not null then raise exception 'invalid_flavors';end if;
 flavors:=array(select trim(f) from unnest(p_flavors) f);
 if exists(select 1 from unnest(flavors) f where length(f) not between 2 and 50 or lower(f) in ('mistas','mista','misturada','misturadas') or f like '%:%') or (select count(distinct lower(f)) from unnest(flavors) f)<>cardinality(flavors) then raise exception 'invalid_flavors';end if;
 -- Lock the affected products before settings, matching order creation's product
 -- locks; an in-flight quote/order sees either complete availability version.
 perform 1 from public.products where category='coxinhas' order by id for update;
 update public.online_shop_settings set coxinha_flavors=flavors where singleton;
 update public.products set allowed_modifiers=allowed_modifiers where category='coxinhas';
 perform app_private.log('menu.coxinha_flavors_updated','category','coxinhas');
end $$;
revoke all on function public.online_set_coxinha_flavors(text[],text) from public,anon,authenticated,service_role;
grant execute on function public.online_set_coxinha_flavors(text[],text) to authenticated;

create function app_private.menu_modifiers(p public.products,mods text[]) returns text[] language plpgsql set search_path='' as $$
begin
 if cardinality(mods)>20 or not mods<@p.allowed_modifiers or (select count(distinct m) from unnest(mods) m)<>cardinality(mods) then raise exception 'invalid_modifier';end if;
 if p.category='coxinhas' then
  if cardinality(p.allowed_modifiers)=0 then raise exception 'flavor_unavailable';end if;
  if cardinality(mods)<>1 or mods[1] not like 'Sabor:%' then raise exception 'flavor_required';end if;
 end if;
 if p.category='pasteis' then
  if cardinality(mods)=0 then return array['Sem acompanhamentos'];end if;
  if 'Sem acompanhamentos'=any(mods) and cardinality(mods)>1 then raise exception 'invalid_modifier';end if;
 end if;
 return mods;
end $$;
revoke all on function app_private.menu_modifiers(public.products,text[]) from public,anon,authenticated;

-- Adicionais chegam como IDs dentro do lanche. O servidor expande em linhas
-- canônicas associadas ao pai, reutilizando baixa de estoque, custos e KDS.
create or replace function app_private.online_items(p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb;p public.products;extra public.products;qty int;mods text[];result jsonb:='[]';total bigint:=0;addons text[];extra_id text;parent_line int;
begin
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'invalid_items';end if;
 perform 1 from public.products where id in(select x->>'product_id' from jsonb_array_elements(p_items) x) or category='adicionais' order by id for share;
 for item in select * from jsonb_array_elements(p_items) loop
  select * into p from public.products where id=item->>'product_id' and active;
  if not found then raise exception 'product_unavailable';end if;
  if p.category='adicionais' then raise exception 'addon_requires_sandwich';end if;
  if coalesce(item->>'quantity','') !~ '^[0-9]{1,3}$' then raise exception 'invalid_quantity';end if;
  qty:=(item->>'quantity')::int;if qty not between 1 and 100 then raise exception 'invalid_quantity';end if;
  if jsonb_typeof(coalesce(item->'modifiers','[]'))<>'array' then raise exception 'invalid_modifier';end if;
  mods:=app_private.menu_modifiers(p,array(select jsonb_array_elements_text(coalesce(item->'modifiers','[]'))));
  if length(coalesce(item->>'notes',''))>500 then raise exception 'notes_too_long';end if;
  if jsonb_typeof(coalesce(item->'addons','[]'))<>'array' then raise exception 'invalid_addons';end if;
  if exists(select 1 from jsonb_array_elements(coalesce(item->'addons','[]')) a where jsonb_typeof(a)<>'string') then raise exception 'invalid_addons';end if;
  addons:=array(select jsonb_array_elements_text(coalesce(item->'addons','[]')));
  if cardinality(addons)>20 or (select count(distinct a) from unnest(addons) a)<>cardinality(addons) then raise exception 'invalid_addons';end if;
  if cardinality(addons)>0 and p.category not in ('hamburgueres','dogoes') then raise exception 'addon_requires_sandwich';end if;
  total:=total+p.price_cents::bigint*qty;
  parent_line:=jsonb_array_length(result)+1;
  result:=result||jsonb_build_array(jsonb_build_object('product_id',p.id,'name',p.name,'quantity',qty,'unit_price_cents',p.price_cents,'sector',p.sector,'modifiers',to_jsonb(mods),'notes',coalesce(item->>'notes','')));
  foreach extra_id in array addons loop
   select * into extra from public.products where id=extra_id and category='adicionais' and active;
   if not found then raise exception 'addon_unavailable';end if;
   total:=total+extra.price_cents::bigint*qty;
   result:=result||jsonb_build_array(jsonb_build_object('product_id',extra.id,'name',extra.name,'quantity',qty,'unit_price_cents',extra.price_cents,'sector',p.sector,'parent_line',parent_line,'modifiers','[]'::jsonb,'notes','Adicional de '||p.name||' · item '||parent_line::text));
  end loop;
  if total>1000000 then raise exception 'order_too_large';end if;
 end loop;
 return jsonb_build_object('items',result,'subtotal_cents',total,'options_version',2);
end $$;

create or replace function public.public_menu() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category',p.category,'description',p.description,'price_cents',p.price_cents,'image_path',p.image_path) order by p.category,p.price_cents,p.name,p.id),'[]')
 from public.products p where p.active and p.category<>'adicionais' and (p.category<>'coxinhas' or cardinality(p.allowed_modifiers)>0)
$$;
create or replace function public.online_assistant_catalog() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('settings',public.online_shop_config(),'products',coalesce(jsonb_agg(jsonb_build_object('product_id',p.id,'name',p.name,'description',p.description,'category',p.category,'image_path',p.image_path,'price_cents',p.price_cents,'allowed_modifiers',p.allowed_modifiers) order by p.category,p.name),'[]')) from public.products p where p.active and (p.category<>'coxinhas' or cardinality(p.allowed_modifiers)>0)
$$;
create or replace function public.create_order(p_key uuid,p_customer text,p_channel text,p_items jsonb) returns public.orders language plpgsql security definer set search_path='' as $$
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
  mods:=app_private.menu_modifiers(product,mods);
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
   app_private.menu_modifiers(product,array(select jsonb_array_elements_text(coalesce(item->'modifiers','[]')))),coalesce(item->>'notes',''));
 end loop;
 return result;
end $$;

create or replace function public.checkout_order(p_token text,p_key uuid,p_tracking text,p_contact jsonb,p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare link public.order_links; result public.orders; item jsonb; product public.products; qty int; mods text[];total bigint:=0;limiter app_private.order_link_secrets;
 request_hash text:=encode(extensions.digest(jsonb_build_object('contact',p_contact,'items',p_items)::text,'sha256'),'hex'); previous_hash text;
begin
 link:=app_private.order_link(p_token);
 if p_key is null or p_tracking is null or p_tracking !~ '^[a-f0-9]{64}$' then raise exception 'invalid_tracking_key';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 select o.* into result from public.orders o join app_private.order_tracking t on t.order_id=o.id where o.idempotency_key=p_key and t.link_id=link.id;
 if found then
  if result.request_body->>'request_hash'<>request_hash or not exists(select 1 from app_private.order_tracking where order_id=result.id and token_hash=encode(extensions.digest(p_tracking,'sha256'),'hex')) then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',result.id,'number',result.number,'total_cents',result.total_cents,'status',result.status);
 end if;
 select * into limiter from app_private.order_link_secrets where link_id=link.id for update;
 if limiter.window_started<now()-interval '1 minute' then update app_private.order_link_secrets set submissions=0,window_started=now() where link_id=link.id;limiter.submissions:=0;end if;
 if limiter.submissions>=10 then raise exception 'checkout_rate_limit';end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'invalid_items';end if;
 if length(trim(p_contact->>'name')) not between 2 and 100 or length(coalesce(p_contact->>'address',''))>500 or length(coalesce(p_contact->>'email',''))>254 then raise exception 'invalid_contact';end if;
 if link.channel='delivery' and (coalesce(p_contact->>'phone','') !~ '^\+?[0-9]{10,15}$' or length(trim(coalesce(p_contact->>'address','')))<10) then raise exception 'delivery_contact_required';end if;
 if coalesce((p_contact->>'whatsapp_consent')::boolean,false) and coalesce(p_contact->>'phone','') !~ '^\+?[0-9]{10,15}$' then raise exception 'phone_required_for_updates';end if;
 perform 1 from public.products where id in(select x->>'product_id' from jsonb_array_elements(p_items) x) order by id for share;
 for item in select * from jsonb_array_elements(p_items) loop
  select * into product from public.products where id=item->>'product_id' and active;if not found then raise exception 'product_unavailable';end if;
  if coalesce(item->>'quantity','') !~ '^[0-9]+$' then raise exception 'invalid_quantity';end if;qty:=(item->>'quantity')::int;if qty not between 1 and 100 then raise exception 'invalid_quantity';end if;
  mods:=array(select jsonb_array_elements_text(coalesce(item->'modifiers','[]')));
  mods:=app_private.menu_modifiers(product,mods);
  if length(coalesce(item->>'notes',''))>500 then raise exception 'notes_too_long';end if;
  total:=total+product.price_cents::bigint*qty;
 end loop;
 if total>1000000 then raise exception 'order_too_large';end if;
 insert into public.orders(source,idempotency_key,request_body,customer,channel,total_cents)
 values('self_service',p_key,jsonb_build_object('request_hash',request_hash),case when link.channel='table' then link.label else 'Delivery' end,link.channel,total) returning * into result;
 for item in select * from jsonb_array_elements(p_items) loop
  select * into product from public.products where id=item->>'product_id';
  insert into public.order_items(order_id,product_id,name,quantity,unit_price_cents,sector,modifiers,notes)
  values(result.id,product.id,product.name,(item->>'quantity')::int,product.price_cents,product.sector,app_private.menu_modifiers(product,array(select jsonb_array_elements_text(coalesce(item->'modifiers','[]')))),coalesce(item->>'notes',''));
 end loop;
 insert into app_private.order_tracking values(result.id,encode(extensions.digest(p_tracking,'sha256'),'hex'),link.id);
 insert into public.customer_contacts(order_id,name,phone,address,email,whatsapp_consent)
 values(result.id,trim(p_contact->>'name'),coalesce(p_contact->>'phone',''),coalesce(p_contact->>'address',''),coalesce(p_contact->>'email',''),coalesce((p_contact->>'whatsapp_consent')::boolean,false));
 update app_private.order_link_secrets set submissions=submissions+1 where link_id=link.id;
 return jsonb_build_object('id',result.id,'number',result.number,'total_cents',result.total_cents,'status',result.status);
end $$;
notify pgrst, 'reload schema';

-- SOURCE: supabase/migrations/20261111163759_private_tables_rls.sql
-- SHA256: 2f1dec2dd81f01ed416c34af346538f1df1fd745ab604e14d03513e4f2051d67
-- Internal tables are accessed through their existing privileged functions.
-- RLS adds a default deny layer if application-role grants change later.
alter table app_private.admin_cost_coverage enable row level security;
alter table app_private.integration_settings enable row level security;
alter table app_private.manual_bank_references enable row level security;
alter table app_private.message_replies enable row level security;
alter table app_private.online_ai_permissions enable row level security;
alter table app_private.online_allocations enable row level security;
alter table app_private.online_change_votes enable row level security;
alter table app_private.online_contacts enable row level security;
alter table app_private.online_handoffs enable row level security;
alter table app_private.online_payment_events enable row level security;
alter table app_private.online_rate_limits enable row level security;
alter table app_private.order_link_secrets enable row level security;
alter table app_private.order_tracking enable row level security;
alter table app_private.payment_artifacts enable row level security;
alter table app_private.pin_credentials enable row level security;
alter table app_private.terminal_attempts enable row level security;
alter table app_private.terminal_leases enable row level security;
alter table app_private.terminal_secrets enable row level security;
alter table app_private.webhook_events enable row level security;

-- SOURCE: supabase/seed.sql
-- SHA256: 4dd8ba86b7a1cc34aaa4a0c21d3d362d4c30cf712a471c733d7c9213a800f2e6
do $$begin perform set_config('app.audit_reason','Carga inicial do cardápio da loja',true);end $$;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('simples','Simples','hamburgueres','Pão e carne de hambúrguer. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',700,'grill','/menu/hamburgueres.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos','Ponto: mal passado','Ponto: ao ponto','Ponto: bem passado']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('cheese-burguer','Cheese Burguer','hamburgueres','Pão, carne de hambúrguer e queijo. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',800,'grill','/menu/hamburgueres.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos','Ponto: mal passado','Ponto: ao ponto','Ponto: bem passado']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('x-burguer','X-Burguer','hamburgueres','Pão, carne de hambúrguer, presunto, queijo e ovo. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',900,'grill','/menu/hamburgueres.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos','Ponto: mal passado','Ponto: ao ponto','Ponto: bem passado']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('x-calabresa','X-Calabresa','hamburgueres','Pão, carne de hambúrguer, calabresa e queijo. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',1200,'grill','/menu/hamburgueres.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos','Ponto: mal passado','Ponto: ao ponto','Ponto: bem passado']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('x-bacon','X-Bacon','hamburgueres','Pão, carne de hambúrguer, bacon e queijo. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',1300,'grill','/menu/hamburgueres.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos','Ponto: mal passado','Ponto: ao ponto','Ponto: bem passado']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('x-egg-bacon','X-Egg Bacon','hamburgueres','Pão, carne de hambúrguer, queijo, ovo e bacon. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',1500,'grill','/menu/hamburgueres.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos','Ponto: mal passado','Ponto: ao ponto','Ponto: bem passado']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('x-tudo','X-Tudo','hamburgueres','Pão, carne de hambúrguer, salsicha, calabresa, bacon, ovo, queijo e presunto. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',1700,'grill','/menu/hamburgueres.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos','Ponto: mal passado','Ponto: ao ponto','Ponto: bem passado']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('dogao','Dogão na chapa','dogoes','Pão, salsicha, presunto e queijo. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',600,'grill','/menu/dogoes.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('dogao-calabresa','Dogão com calabresa','dogoes','Dogão com calabresa. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',800,'grill','/menu/dogoes.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('dogao-bacon','Dogão com bacon','dogoes','Dogão com bacon. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',900,'grill','/menu/dogoes.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('dogao-duplo','Dogão duplo','dogoes','Pão, 2 salsichas, 2 presuntos e 2 queijos. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',1200,'grill','/menu/dogoes.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('x-dogao','X-Dogão especial','dogoes','Pão, salsicha, presunto, queijo, calabresa e bacon. Alface, tomate, cebola caramelizada, milho, batata palha e molhos da casa.',1500,'grill','/menu/dogoes.svg',ARRAY['Sem cebola','Sem tomate','Sem alface','Sem molhos']::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('batata','Batata frita','porcoes','Porção conforme o cardápio da casa.',800,'fryer','/menu/porcoes.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('batata-calabresa','Batata com calabresa','porcoes','Porção conforme o cardápio da casa.',1200,'fryer','/menu/porcoes.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('batata-bacon','Batata com bacon','porcoes','Porção conforme o cardápio da casa.',1200,'fryer','/menu/porcoes.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('pastel-frango','Frango com queijo','pasteis','Pastel preparado na hora.',800,'fryer','/menu/pasteis.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('pastel-calabresa','Queijo com calabresa','pasteis','Pastel preparado na hora.',800,'fryer','/menu/pasteis.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('pastel-misto','Misto','pasteis','Pastel preparado na hora.',800,'fryer','/menu/pasteis.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coxinhas-5','Mini coxinhas · 5 unidades','coxinhas','Porção com 5 mini coxinhas.',100,'fryer','/menu/coxinhas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coxinhas-10','Mini coxinhas · 10 unidades','coxinhas','Porção com 10 mini coxinhas.',200,'fryer','/menu/coxinhas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coxinhas-15','Mini coxinhas · 15 unidades','coxinhas','Porção com 15 mini coxinhas.',300,'fryer','/menu/coxinhas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coxinhas-20','Mini coxinhas · 20 unidades','coxinhas','Porção com 20 mini coxinhas.',400,'fryer','/menu/coxinhas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coxinhas-25','Mini coxinhas · 25 unidades','coxinhas','Porção com 25 mini coxinhas.',500,'fryer','/menu/coxinhas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coxinhas-35','Mini coxinhas · 35 unidades','coxinhas','Porção com 35 mini coxinhas.',700,'fryer','/menu/coxinhas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coxinhas-50','Mini coxinhas · 50 unidades','coxinhas','Porção com 50 mini coxinhas.',1000,'fryer','/menu/coxinhas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coxinhas-75','Mini coxinhas · 75 unidades','coxinhas','Porção com 75 mini coxinhas.',1500,'fryer','/menu/coxinhas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coxinhas-100','Mini coxinhas · 100 unidades','coxinhas','Porção com 100 mini coxinhas.',2000,'fryer','/menu/coxinhas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coxinhas-125','Mini coxinhas · 125 unidades','coxinhas','Porção com 125 mini coxinhas.',2500,'fryer','/menu/coxinhas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('refri-lata','Refrigerante lata','bebidas','',500,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coca-lata','Coca-Cola lata','bebidas','',600,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('refri-1l','Refrigerante 1 L','bebidas','',800,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('coca-1l','Coca-Cola 1 L','bebidas','',1000,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('del-valle','Del Valle','bebidas','',500,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('polpa','Suco de polpa','bebidas','',200,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('agua','Água','bebidas','',200,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('pet-2','Santa Joana 200 ml','bebidas','Refrigerante Santa Joana, garrafa de 200 ml.',200,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('pet-3','Antarctica 200 ml','bebidas','Refrigerante Antarctica, garrafa de 200 ml.',300,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('h2o','H2O','bebidas','',600,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('agua-gas','Água com gás','bebidas','',300,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('santa-joana','Santa Joana 2 L','bebidas','',800,'bar','/menu/bebidas.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('extra-carne','Carne de hambúrguer','adicionais','Adicional para o seu lanche.',200,'grill','/menu/adicionais.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('extra-salsicha','Salsicha','adicionais','Adicional para o seu lanche.',200,'grill','/menu/adicionais.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('extra-presunto','Presunto','adicionais','Adicional para o seu lanche.',100,'grill','/menu/adicionais.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('extra-queijo','Queijo','adicionais','Adicional para o seu lanche.',100,'grill','/menu/adicionais.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('extra-ovo','Ovo','adicionais','Adicional para o seu lanche.',100,'grill','/menu/adicionais.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('extra-calabresa','Calabresa','adicionais','Adicional para o seu lanche.',300,'grill','/menu/adicionais.svg',ARRAY[]::text[]) on conflict(id) do nothing;
insert into public.products(id,name,category,description,price_cents,sector,image_path,allowed_modifiers) values('extra-bacon','Bacon','adicionais','Adicional para o seu lanche.',300,'grill','/menu/adicionais.svg',ARRAY[]::text[]) on conflict(id) do nothing;

-- SOURCE: supabase/activation/04_restringir_rpc.sql
-- SHA256: 8eabc26c5b64e29e59879a379775663a1a29387a12da6fd50519b4e2eef06f7d
-- O EXECUTE global concedido a PUBLIC também alcança anon/authenticated.
-- REVOKE em ALTER DEFAULT PRIVILEGES IN SCHEMA não remove o padrão global.
-- Preserva todos os GRANTs explícitos dos contratos 001–018.

revoke execute on all functions in schema public from public;
alter default privileges revoke execute on functions from public;

-- Pedidos públicos começam pausados. Cadastre a loja e homologue antes de abrir.
update public.online_shop_settings set enabled = false, delivery_enabled = false;
commit;
