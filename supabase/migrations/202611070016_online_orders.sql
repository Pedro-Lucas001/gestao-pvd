begin;
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
commit;
