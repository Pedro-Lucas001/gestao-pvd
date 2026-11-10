begin;
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
commit;
