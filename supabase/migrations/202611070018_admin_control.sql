begin;
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
commit;
