begin;

alter table public.online_shop_settings
  add column schedule_enabled boolean not null default false,
  add column weekly_hours jsonb not null default '[
    null,
    {"opens":"18:00","closes":"23:00"},
    {"opens":"18:00","closes":"23:00"},
    {"opens":"18:00","closes":"23:00"},
    {"opens":"18:00","closes":"23:00"},
    {"opens":"18:00","closes":"23:00"},
    {"opens":"18:00","closes":"23:00"}
  ]',
  add column delivery_areas_enabled boolean not null default false,
  add column delivery_areas jsonb not null default '[]';

create function app_private.within_online_hours(p_hours jsonb, p_at timestamptz)
returns boolean language sql immutable set search_path='' as $$
  with local_time as (
    select p_at at time zone 'America/Recife' as at
  ), day_windows as (
    select at::time as clock,
      p_hours->(extract(isodow from at)::int-1) as today,
      p_hours->((extract(isodow from at)::int+5)%7) as yesterday
    from local_time
  )
  select coalesce(
    (clock >= (today->>'opens')::time and
      ((today->>'closes')::time < (today->>'opens')::time or clock < (today->>'closes')::time))
    or ((yesterday->>'closes')::time < (yesterday->>'opens')::time and clock < (yesterday->>'closes')::time),
    false)
  from day_windows
$$;

create or replace function public.online_shop_config()
returns jsonb language sql stable security definer set search_path='' as $$
  select (to_jsonb(s) - 'singleton') || jsonb_build_object(
    'accepting_orders', s.enabled and (not s.schedule_enabled or
      app_private.within_online_hours(s.weekly_hours, statement_timestamp())))
  from public.online_shop_settings s where singleton
$$;

create function public.online_save_delivery_rules(
  p_schedule boolean, p_hours jsonb, p_restrict_areas boolean, p_areas jsonb, p_reason text
)
returns void language plpgsql security definer set search_path='' as $$
declare
  entry jsonb;
  area_name text;
  area_id text;
  names text[] := '{}';
  ids text[] := '{}';
  areas jsonb := '[]';
  time_pattern constant text := '^([01][0-9]|2[0-3]):[0-5][0-9]$';
begin
  if not app_private.is_admin() then
    raise exception 'access_denied' using errcode='42501';
  end if;
  if p_schedule is null or jsonb_typeof(p_hours) is distinct from 'array' then
    raise exception 'invalid_online_hours';
  end if;
  if jsonb_array_length(p_hours) <> 7 then raise exception 'invalid_online_hours'; end if;
  for entry in select value from jsonb_array_elements(p_hours) loop
    if entry = 'null' then continue; end if;
    if jsonb_typeof(entry) is distinct from 'object'
      or coalesce(entry->>'opens','') !~ time_pattern
      or coalesce(entry->>'closes','') !~ time_pattern
      or entry->>'opens' = entry->>'closes'
      or entry - 'opens' - 'closes' <> '{}' then
      raise exception 'invalid_online_hours';
    end if;
  end loop;
  if p_restrict_areas is null or jsonb_typeof(p_areas) is distinct from 'array' then
    raise exception 'invalid_delivery_areas';
  end if;
  if jsonb_array_length(p_areas) > 100 then raise exception 'invalid_delivery_areas'; end if;
  if p_restrict_areas and jsonb_array_length(p_areas) = 0 then
    raise exception 'delivery_areas_empty';
  end if;
  for entry in select value from jsonb_array_elements(p_areas) loop
    area_name := regexp_replace(trim(coalesce(entry->>'name','')), '[[:space:]]+', ' ', 'g');
    area_name := trim(area_name);
    area_id := coalesce(entry->>'id','');
    if jsonb_typeof(entry->'name') is distinct from 'string'
      or length(area_name) not between 2 and 80
      or area_id !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
      or jsonb_typeof(entry->'fee_cents') is distinct from 'number'
      or coalesce(entry->>'fee_cents','') !~ '^[0-9]{1,6}$' then
      raise exception 'invalid_delivery_areas';
    end if;
    if (entry->>'fee_cents')::int > 100000 then raise exception 'invalid_delivery_areas'; end if;
    if lower(area_name) = any(names) or area_id = any(ids) then
      raise exception 'duplicate_delivery_area';
    end if;
    names := array_append(names, lower(area_name));
    ids := array_append(ids, area_id);
    areas := areas || jsonb_build_array(jsonb_build_object(
      'id',area_id, 'name',area_name, 'fee_cents',(entry->>'fee_cents')::int));
  end loop;
  perform app_private.reason(p_reason);
  update public.online_shop_settings
  set schedule_enabled = p_schedule, weekly_hours = p_hours,
      delivery_areas_enabled = p_restrict_areas, delivery_areas = areas
  where singleton;
  perform app_private.log('online.delivery_rules_updated','shop','online');
end $$;

create function app_private.online_area_quote(p_items jsonb, p_fulfillment text, p_area text)
returns jsonb language plpgsql set search_path='' as $$
declare
  settings public.online_shop_settings;
  cart jsonb;
  area jsonb;
  fee int := 0;
  total int;
begin
  select * into settings from public.online_shop_settings where singleton;
  if not settings.enabled then raise exception 'shop_closed'; end if;
  if settings.schedule_enabled and not app_private.within_online_hours(settings.weekly_hours, statement_timestamp()) then
    raise exception 'outside_order_hours';
  end if;
  if p_fulfillment is null or p_fulfillment not in ('pickup','delivery') then
    raise exception 'invalid_fulfillment';
  end if;
  if p_fulfillment = 'delivery' then
    if not settings.delivery_enabled then raise exception 'delivery_unavailable'; end if;
    fee := settings.delivery_fee_cents;
    if settings.delivery_areas_enabled then
      if coalesce(p_area,'') = '' then raise exception 'delivery_area_required'; end if;
      select value into area from jsonb_array_elements(settings.delivery_areas) where value->>'id' = p_area;
      if not found then raise exception 'delivery_area_unavailable'; end if;
      fee := (area->>'fee_cents')::int;
    end if;
  end if;
  cart := app_private.online_items(p_items);
  total := (cart->>'subtotal_cents')::int + fee;
  if total > 1000000 then raise exception 'order_too_large'; end if;
  return cart || jsonb_build_object('delivery_fee_cents',fee,'delivery_area',area->>'name','total_cents',total);
end $$;

create or replace function public.online_quote(p_items jsonb, p_fulfillment text)
returns jsonb language sql security definer set search_path='' as $$
  select app_private.online_area_quote(p_items, p_fulfillment, null) - 'delivery_area'
$$;

create function public.online_delivery_quote(p_items jsonb, p_fulfillment text, p_method text, p_area text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  quote jsonb;
  fee int := 0;
  total int;
begin
  if p_method is null or p_method not in ('pix','cash','card','card_delivery') then
    raise exception 'payment_unavailable';
  end if;
  if p_method = 'card_delivery' and (p_fulfillment is distinct from 'delivery'
    or not (select delivery_card_enabled from public.online_shop_settings where singleton)) then
    raise exception 'payment_unavailable';
  end if;
  quote := app_private.online_area_quote(p_items, p_fulfillment, p_area);
  total := (quote->>'total_cents')::int;
  if p_method = 'card_delivery' then fee := app_private.delivery_card_fee(total); end if;
  if total + fee > 1000000 then raise exception 'order_too_large'; end if;
  return quote || jsonb_build_object('card_fee_cents',fee,'card_fee_percent',
    case when p_method = 'card_delivery' then 6 else 0 end,'total_cents',total+fee);
end $$;

create or replace function public.online_delivery_quote(p_items jsonb, p_fulfillment text, p_method text)
returns jsonb language sql security definer set search_path='' as $$
  select public.online_delivery_quote(p_items, p_fulfillment, p_method, null) - 'delivery_area'
$$;

create or replace function public.online_create_order(p_key uuid,p_tracking text,p_items jsonb,p_contact jsonb,p_fulfillment text,p_method text,p_change_for int,p_expected_total int) returns jsonb language plpgsql security definer set search_path='' as $$
declare q jsonb;o public.online_orders;h text;delivery_address text;s public.online_shop_settings;
begin
 if p_key is null or p_tracking is null or p_tracking !~ '^[a-f0-9]{64}$' then raise exception 'invalid_tracking_key';end if;
 h:=encode(extensions.digest(jsonb_build_object('items',p_items,'contact',p_contact,'fulfillment',p_fulfillment,'method',p_method,'change_for',p_change_for,'total',p_expected_total)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_key::text,16));
 select * into o from public.online_orders where idempotency_key=p_key;
 if found then
  if o.request_hash<>h or o.token_hash<>encode(extensions.digest(p_tracking,'sha256'),'hex') then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',o.id,'number',o.number,'total_cents',o.total_cents,'status',o.status);
 end if;
 select * into s from public.online_shop_settings where singleton for share;
 if p_method is null or p_method not in ('pix','card','cash','card_delivery') or (p_method='cash' and not s.cash_enabled) then raise exception 'payment_unavailable';end if;
 if p_contact is null or length(trim(coalesce(p_contact->>'name',''))) not between 2 and 100 or coalesce(p_contact->>'phone','') !~ '^[0-9]{10,15}$' or length(coalesce(p_contact->>'email',''))>254 or length(coalesce(p_contact->>'address',''))>500 then raise exception 'invalid_contact';end if;
 if (p_method in ('pix','card') or coalesce(p_contact->>'email','')<>'') and coalesce(p_contact->>'email','') !~ '^[^ @]+@[^ @]+\.[^ @]+$' then raise exception 'email_required';end if;
 if p_fulfillment='delivery' and length(trim(coalesce(p_contact->>'address','')))<10 then raise exception 'delivery_contact_required';end if;
 if length(coalesce(p_contact->>'reference',''))>200 or (p_fulfillment='delivery' and length(trim(coalesce(p_contact->>'reference','')))<2) then raise exception 'delivery_reference_required';end if;
 q:=public.online_delivery_quote(p_items,p_fulfillment,p_method,p_contact->>'delivery_area_id');
 delivery_address:=coalesce(p_contact->>'address','');
 if q->>'delivery_area' is not null then
  delivery_address:=trim(delivery_address)||' · Bairro: '||(q->>'delivery_area');
 end if;
 if p_expected_total is null or p_expected_total<>(q->>'total_cents')::int then raise exception 'price_changed_review_order';end if;
 if p_change_for is not null and (p_method<>'cash' or p_change_for<p_expected_total or p_change_for>1000000) then raise exception 'invalid_change_amount';end if;
 insert into public.online_orders(token_hash,idempotency_key,request_hash,status,fulfillment,payment_method,items,subtotal_cents,delivery_fee_cents,total_cents,cash_change_for_cents,card_fee_cents,pay_on_delivery,cash_authorized)
 values(encode(extensions.digest(p_tracking,'sha256'),'hex'),p_key,h,case when p_method='cash' then 'awaiting_store' else 'payment_pending' end,p_fulfillment,p_method,q->'items',(q->>'subtotal_cents')::int,(q->>'delivery_fee_cents')::int,p_expected_total,p_change_for,(q->>'card_fee_cents')::int,p_fulfillment='delivery' and p_method<>'card',p_fulfillment='delivery' and p_method='cash') returning * into o;
 insert into app_private.online_contacts(order_id,name,phone,email,address,whatsapp_consent,reference) values(o.id,trim(p_contact->>'name'),p_contact->>'phone',coalesce(p_contact->>'email',''),delivery_address,coalesce((p_contact->>'whatsapp_consent')::boolean,false),trim(coalesce(p_contact->>'reference','')));
 insert into app_private.online_tracking_links values(o.id,p_tracking);
 insert into public.online_notifications(order_id,topic,revision) values(o.id,'order.received',o.revision);
 if o.pay_on_delivery then perform app_private.online_release(o.id);select * into o from public.online_orders where id=o.id;end if;
 if p_method='pix' then insert into public.online_notifications(order_id,topic,revision) values(o.id,'order.payment_requested',o.revision);end if;
 return jsonb_build_object('id',o.id,'number',o.number,'total_cents',o.total_cents,'status',o.status);
end $$;

revoke all on function app_private.within_online_hours(jsonb,timestamptz),
  app_private.online_area_quote(jsonb,text,text) from public,anon,authenticated,service_role;
revoke all on function public.online_save_delivery_rules(boolean,jsonb,boolean,jsonb,text),
  public.online_delivery_quote(jsonb,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.online_save_delivery_rules(boolean,jsonb,boolean,jsonb,text) to authenticated;
grant execute on function public.online_delivery_quote(jsonb,text,text,text) to service_role;

notify pgrst, 'reload schema';

commit;
