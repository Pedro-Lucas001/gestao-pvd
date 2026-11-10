\set ON_ERROR_STOP on
\o /dev/null
begin;
select set_config('app.audit_reason','Fixtures isoladas de personalizacao do cardapio',true);
create function pg_temp.assert(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'ASSERT: %',msg;end if;end $$;
grant execute on function pg_temp.assert(boolean,text) to anon,authenticated,service_role;
insert into auth.users(id) values('f0000000-0000-0000-0000-000000000001'),('f0000000-0000-0000-0000-000000000002');
update public.profiles set role='admin',active=true where id='f0000000-0000-0000-0000-000000000001';
update public.profiles set role='cashier',active=true where id='f0000000-0000-0000-0000-000000000002';
update public.online_shop_settings set enabled=true,delivery_enabled=true,delivery_fee_cents=500;
insert into public.products(id,name,category,price_cents,sector,image_path,allowed_modifiers) values
 ('custom-burger','Burger teste','hamburgueres',1000,'grill','/menu/hamburgueres.svg',array['Sem cebola','Ponto: ao ponto']),
 ('custom-dog','Dog teste','dogoes',600,'grill','/menu/dogoes.svg','{}'),
 ('custom-pastel','Pastel teste','pasteis',800,'fryer','/menu/pasteis.svg','{}'),
 ('custom-coxinha','Coxinha teste','coxinhas',200,'fryer','/menu/coxinhas.svg','{}'),
 ('custom-extra','Bacon teste','adicionais',300,'grill','/menu/adicionais.svg','{}');
insert into public.ingredients(id,name,unit,stock,unit_cost_cents) values('f1000000-0000-0000-0000-000000000001','Carne teste','un',100,100),('f1000000-0000-0000-0000-000000000002','Bacon teste','g',100,10);
insert into public.recipe_items values('custom-burger','f1000000-0000-0000-0000-000000000001',1),('custom-extra','f1000000-0000-0000-0000-000000000002',2);
select pg_temp.assert((select not ('Ponto: ao ponto'=any(allowed_modifiers)) and description like '%industrializadas%' from public.products where id='custom-burger'),'produtos novos tambem removem ponto e informam carnes industriais');
select pg_temp.assert(not exists(select 1 from jsonb_array_elements(public.public_menu()) p where p->>'category'='adicionais'),'adicionais nao sao compras independentes no mostruario');
set local role service_role;
select set_config('test.items','[{"product_id":"custom-burger","quantity":2,"price_cents":1,"addons":["custom-extra"]}]',true);
select set_config('test.quote',public.online_delivery_quote(current_setting('test.items')::jsonb,'delivery','cash')::text,true);
select pg_temp.assert(current_setting('test.quote')::jsonb->>'total_cents'='3100','preco canonico inclui dois lanches, dois adicionais e entrega');
select pg_temp.assert(current_setting('test.quote')::jsonb#>>'{items,1,parent_line}'='1' and current_setting('test.quote')::jsonb#>>'{items,1,quantity}'='2','adicional guarda associacao ao lanche e acompanha quantidade');
do $$begin
 begin perform public.online_quote('[{"product_id":"custom-pastel","quantity":1,"addons":["custom-extra"]}]','pickup');raise exception 'ASSERT: adicional em pastel';exception when raise_exception then if sqlerrm<>'addon_requires_sandwich' then raise;end if;end;
 begin perform public.online_quote('[{"product_id":"custom-extra","quantity":1}]','pickup');raise exception 'ASSERT: adicional avulso';exception when raise_exception then if sqlerrm<>'addon_requires_sandwich' then raise;end if;end;
 begin perform public.online_quote('[{"product_id":"custom-burger","quantity":1,"addons":["custom-extra","custom-extra"]}]','pickup');raise exception 'ASSERT: adicional duplicado';exception when raise_exception then if sqlerrm<>'invalid_addons' then raise;end if;end;
 begin perform public.online_quote('[{"product_id":"custom-burger","quantity":1,"modifiers":["Ponto: ao ponto"]}]','pickup');raise exception 'ASSERT: ponto aceito';exception when raise_exception then if sqlerrm<>'invalid_modifier' then raise;end if;end;
 begin perform public.online_quote('[{"product_id":"custom-coxinha","quantity":1}]','pickup');raise exception 'ASSERT: coxinha sem sabor';exception when raise_exception then if sqlerrm<>'flavor_required' then raise;end if;end;
end $$;
select pg_temp.assert(public.online_quote('[{"product_id":"custom-pastel","quantity":1,"modifiers":["Com tomate","Com milho","Com batata palha","Com ketchup","Com maionese"]}]','pickup')->>'total_cents'='800','pastel conserva preco com os cinco acompanhamentos');
select pg_temp.assert(public.online_quote('[{"product_id":"custom-pastel","quantity":1}]','pickup')#>>'{items,0,modifiers,0}'='Sem acompanhamentos','cozinha recebe instrucao explicita sem acompanhamentos');
select set_config('test.order',(public.online_create_order('f2000000-0000-0000-0000-000000000001',repeat('f',64),current_setting('test.items')::jsonb,'{"name":"Cliente teste","phone":"5581999999999","address":"Rua de teste numero 10","reference":"Perto da praca","whatsapp_consent":false}','delivery','cash',null,3100)->>'id'),true);
select public.online_create_order('f2000000-0000-0000-0000-000000000001',repeat('f',64),current_setting('test.items')::jsonb,'{"name":"Cliente teste","phone":"5581999999999","address":"Rua de teste numero 10","reference":"Perto da praca","whatsapp_consent":false}','delivery','cash',null,3100);
reset role;
select pg_temp.assert((select stock=98 from public.ingredients where id='f1000000-0000-0000-0000-000000000001') and (select stock=96 from public.ingredients where id='f1000000-0000-0000-0000-000000000002'),'estoque de lanche e adicional baixa uma vez');
select pg_temp.assert((select payload#>>'{items,1,parent_line}'='1' and payload#>>'{items,1,notes}' like 'Adicional de Burger teste%' from app_private.online_print_jobs where order_id=current_setting('test.order')::uuid),'impressao guarda associacao do adicional');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f0000000-0000-0000-0000-000000000002"}',true);
do $$begin
 begin perform public.online_set_coxinha_flavors(array['Frango'],'Tentativa nao autorizada');raise exception 'ASSERT: caixa alterou disponibilidade';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims','{"sub":"f0000000-0000-0000-0000-000000000001"}',true);
select public.online_set_coxinha_flavors(array['Frango'],'Hoje ha somente sabor frango');
reset role;
select pg_temp.assert((select allowed_modifiers=array['Sabor: Frango'] from public.products where id='custom-coxinha'),'disponibilidade altera todas as porcoes sem mistura com sabor ausente');
set local role service_role;
do $$begin
 begin perform public.online_quote('[{"product_id":"custom-coxinha","quantity":1,"modifiers":["Sabor: Mistas"]}]','pickup');raise exception 'ASSERT: mistura indisponivel';exception when raise_exception then if sqlerrm<>'invalid_modifier' then raise;end if;end;
end $$;
select pg_temp.assert(public.online_quote('[{"product_id":"custom-coxinha","quantity":1,"modifiers":["Sabor: Frango"]}]','pickup')->>'total_cents'='200','sabor disponivel aceito');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f0000000-0000-0000-0000-000000000001"}',true);
select public.online_set_coxinha_flavors('{}','Mini coxinhas esgotaram hoje');
select pg_temp.assert(not exists(select 1 from jsonb_array_elements(public.public_menu()) p where p->>'category'='coxinhas'),'sem sabores todas as porcoes saem do mostruario');
select public.online_set_coxinha_flavors(array['Frango','Presunto'],'Reposicao dos dois sabores padrao');
set local role service_role;
select pg_temp.assert(public.online_quote('[{"product_id":"custom-coxinha","quantity":1,"modifiers":["Sabor: Mistas"]}]','pickup')->>'total_cents'='200','misturada disponivel apos reposicao');
reset role;
update public.products set active=false where id='custom-extra';
set local role service_role;
do $$begin
 begin perform public.online_quote(current_setting('test.items')::jsonb,'pickup');raise exception 'ASSERT: adicional inativo';exception when raise_exception then if sqlerrm<>'addon_unavailable' then raise;end if;end;
end $$;
reset role;
select pg_temp.assert((select total_cents=3100 and items#>>'{1,name}'='Bacon teste' from public.online_orders where id=current_setting('test.order')::uuid),'mudanca diaria nao altera pedido ja criado');
rollback;
\o
\echo 'Menu options: canonical attached extras, stock, print, industrial meat, pastries and daily flavors passed.'
