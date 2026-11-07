\set ON_ERROR_STOP on
begin;
create function pg_temp.assert(ok boolean, message text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'ASSERTION FAILED: %', message; end if; end $$;
grant execute on function pg_temp.assert(boolean,text) to anon,authenticated,service_role;
select set_config('app.audit_reason','Teste isolado de publicação do cardápio',true);
insert into public.products(id,name,category,description,price_cents,sector,image_path,active)
values ('menu-test-public','Produto público','bebidas','Descrição pública',1200,'bar','/menu/bebidas.svg',true),
       ('menu-test-hidden','Produto oculto','bebidas','Nunca publicar',1800,'bar','/menu/bebidas.svg',false);
set local role anon;
select pg_temp.assert(jsonb_typeof(public.public_menu())='array','anonymous catalog must be an array');
select pg_temp.assert(exists(select 1 from jsonb_array_elements(public.public_menu()) p where p->>'id'='menu-test-public' and p->>'price_cents'='1200'),'anonymous visitor sees active item and canonical price');
select pg_temp.assert(not exists(select 1 from jsonb_array_elements(public.public_menu()) p where p->>'id'='menu-test-hidden'),'inactive product is hidden');
select pg_temp.assert(not exists(select 1 from jsonb_array_elements(public.public_menu()) p cross join lateral jsonb_object_keys(p) k where k not in ('id','name','category','description','price_cents','image_path')),'only allowlisted presentation fields are public');
do $$ begin
  begin perform 1 from public.profiles; raise exception 'anonymous profiles leaked'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.orders; raise exception 'anonymous orders leaked'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.ingredients; raise exception 'anonymous costs leaked'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.products; raise exception 'anonymous base table exposed'; exception when insufficient_privilege then null; end;
  begin perform public.admin_metrics(now()-interval '1 day',now()); raise exception 'anonymous metrics allowed'; exception when insufficient_privilege then null; end;
  begin perform public.open_shift(0); raise exception 'anonymous cash operation allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.products set price_cents=1300 where id='menu-test-public';
set local role anon;
select pg_temp.assert(exists(select 1 from jsonb_array_elements(public.public_menu()) p where p->>'id'='menu-test-public' and p->>'price_cents'='1300'),'public catalog reflects the managed product price');
reset role;
update public.products set active=false where id='menu-test-public';
set local role anon;
select pg_temp.assert(not exists(select 1 from jsonb_array_elements(public.public_menu()) p where p->>'id'='menu-test-public'),'removing an item removes it from public catalog');
reset role;
rollback;
\echo 'Cardápio público: campos mínimos, produtos ativos e isolamento anônimo aprovados.'
