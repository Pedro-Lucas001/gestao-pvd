\set ON_ERROR_STOP on
\o /dev/null
begin;
select set_config('app.audit_reason','Fixtures isoladas do controle administrativo',true);
create function pg_temp.assert(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'ASSERT: %',msg;end if;end $$;
insert into auth.users(id) values('d0000000-0000-0000-0000-000000000001'),('d0000000-0000-0000-0000-000000000002'),('d0000000-0000-0000-0000-000000000003');
update public.profiles set role='admin',active=true where id='d0000000-0000-0000-0000-000000000001';
update public.profiles set role='cashier',active=true where id='d0000000-0000-0000-0000-000000000002';
update public.profiles set role='kitchen',sector='grill',active=false where id='d0000000-0000-0000-0000-000000000003';
select set_config('test.reference',(now() at time zone 'America/Recife')::date::text,true);
set local role anon;
do $$begin
 begin perform public.admin_control_snapshot();raise exception 'ASSERT: visitante viu finanças';exception when insufficient_privilege then null;end;
 begin insert into storage.objects(bucket_id,name) values('planeta-product-images','dddddddd-dddd-4ddd-8ddd-dddddddddddd.webp');raise exception 'ASSERT: upload anônimo';exception when insufficient_privilege then null;end;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"d0000000-0000-0000-0000-000000000002","session_id":"admin-test"}',true);
do $$begin
 begin perform public.admin_control_snapshot();raise exception 'ASSERT: caixa viu finanças';exception when insufficient_privilege then null;end;
 begin insert into storage.objects(bucket_id,name) values('planeta-product-images','dddddddd-dddd-4ddd-8ddd-dddddddddddd.webp');raise exception 'ASSERT: caixa trocou foto';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims','{"sub":"d0000000-0000-0000-0000-000000000001","session_id":"admin-test"}',true);
insert into storage.objects(bucket_id,name) values('planeta-product-images','dddddddd-dddd-4ddd-8ddd-dddddddddddd.webp');
select public.save_product('{"id":"admin-test-burger","name":"Burger teste","category":"hamburgueres","price_cents":1000,"sector":"grill","image_path":"/storage/v1/object/public/planeta-product-images/dddddddd-dddd-4ddd-8ddd-dddddddddddd.webp"}','Cadastro de produto com foto própria');
select public.save_product('{"id":"admin-test-burger","name":"Burger teste editado","category":"hamburgueres","price_cents":1000,"sector":"grill"}','Edição preservando a foto anterior');
select pg_temp.assert((select image_path='/storage/v1/object/public/planeta-product-images/dddddddd-dddd-4ddd-8ddd-dddddddddddd.webp' from public.products where id='admin-test-burger'),'edição sem foto não apaga foto própria');
delete from storage.objects where bucket_id='planeta-product-images' and name='dddddddd-dddd-4ddd-8ddd-dddddddddddd.webp';
select pg_temp.assert((select count(*)=1 from storage.objects where name='dddddddd-dddd-4ddd-8ddd-dddddddddddd.webp'),'foto em uso não pode ser apagada');
do $$begin
 begin perform public.save_product('{"id":"admin-evil","name":"Produto","category":"bebidas","price_cents":100,"sector":"bar","image_path":"https://attacker.test/pixel.png"}','Tentativa de imagem externa');raise exception 'ASSERT: imagem externa aceita';exception when raise_exception then if sqlerrm<>'invalid_product_image' then raise;end if;end;
end $$;
select public.set_staff_pin('d0000000-0000-0000-0000-000000000002','8989');
select public.set_staff_pin('d0000000-0000-0000-0000-000000000001','7878');
do $$begin
 begin perform public.admin_save_staff_access('d0000000-0000-0000-0000-000000000003','cashier',null,true,'8989','Ativação com PIN que já existe');raise exception 'ASSERT: PIN repetido aceito';exception when raise_exception then if sqlerrm<>'staff_pin_in_use' then raise;end if;end;
end $$;
select pg_temp.assert((select not active and role='kitchen' from public.profiles where id='d0000000-0000-0000-0000-000000000003'),'PIN duplicado reverte também ativação e função');
select public.admin_save_staff_access('d0000000-0000-0000-0000-000000000003','kitchen','grill',true,'6767','Ativação individual da cozinha');
reset role;
select pg_temp.assert((select extensions.crypt('6767',pin_hash)=pin_hash and pin_hash<>'6767' from app_private.pin_credentials where user_id='d0000000-0000-0000-0000-000000000003'),'PIN pessoal guardado como hash');
insert into public.ingredients(id,name,unit,stock,minimum_stock,unit_cost_cents) values('d1000000-0000-0000-0000-000000000001','Insumo fracionário','g',100,25,12.5),('d1000000-0000-0000-0000-000000000002','Insumo a repor','un',-2,3,100);
insert into public.recipe_items values('admin-test-burger','d1000000-0000-0000-0000-000000000001',4);
create function pg_temp.pos_fixture(ident uuid,total int,qty int,at_time timestamptz) returns void language plpgsql as $$begin
 insert into public.orders(id,source,idempotency_key,request_body,customer,channel,total_cents,subtotal_cents,discount_cents) values(ident,'self_service',ident,'{}','Cliente fictício','counter',total,1000*qty,1000*qty-total);
 insert into public.order_items(order_id,product_id,name,quantity,unit_price_cents,sector) values(ident,'admin-test-burger','Burger teste',qty,1000,'grill');
 insert into public.payment_attempts(id,order_id,method,status,amount_cents,confirmed_at) values(ident,ident,'cash','confirmed',total,at_time);
 insert into public.stock_movements(order_id,ingredient_id,quantity,created_at) values(ident,'d1000000-0000-0000-0000-000000000001',-4*qty,at_time);
 update public.ingredients set stock=stock-4*qty where id='d1000000-0000-0000-0000-000000000001';
 update public.orders set status='queued',paid_at=at_time where id=ident;
end $$;
select pg_temp.pos_fixture('d2000000-0000-0000-0000-000000000001',2000,2,(current_setting('test.reference')::date::timestamp at time zone 'America/Recife')+interval '30 minutes');
-- 02:59:59 UTC ainda é o dia anterior em Recife.
select pg_temp.pos_fixture('d2000000-0000-0000-0000-000000000002',500,1,(current_setting('test.reference')::date::timestamp at time zone 'America/Recife')-interval '1 second');
insert into public.refunds(id,order_id,payment_id,requested_by,amount_cents,reason,state,confirmed_at) values('d3000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000001',2000,'Devolução confirmada no teste','confirmed',now());
update public.payment_attempts set status='refunded' where id='d2000000-0000-0000-0000-000000000001';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('test.online',(public.online_create_order('d4000000-0000-0000-0000-000000000001',repeat('d',64),'[{"product_id":"admin-test-burger","quantity":1}]','{"name":"Cliente","phone":"5581888888888","email":"fixture@example.test","whatsapp_consent":false}','pickup','pix',null,1000)->>'id'),true);
select public.online_prepare_payment(repeat('d',64),'d5000000-0000-0000-0000-000000000001');
select public.online_confirm_payment('d5000000-0000-0000-0000-000000000001',1000,'mp:admin1','mercadopago','admin1','hash1');
select public.online_request_change(repeat('d',64),'d6000000-0000-0000-0000-000000000001','[{"product_id":"admin-test-burger","quantity":2}]','Adicionar outro burger no teste',2000);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"d0000000-0000-0000-0000-000000000001","session_id":"admin-test"}',true);
select public.online_review_change('d6000000-0000-0000-0000-000000000001',true,'Cozinha confirmou a adição de teste');
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.online_prepare_payment(repeat('d',64),'d5000000-0000-0000-0000-000000000002');
select public.online_confirm_payment('d5000000-0000-0000-0000-000000000002',1000,'mp:admin2','mercadopago','admin2','hash2');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"d0000000-0000-0000-0000-000000000001","session_id":"admin-test"}',true);
select public.record_operating_expense('d7000000-0000-0000-0000-000000000001','Despesa de teste',300,current_setting('test.reference')::date,'Despesa real cadastrada na fixture');
select set_config('test.snapshot',public.admin_control_snapshot()::text,true);
select pg_temp.assert((current_setting('test.snapshot')::jsonb#>>'{periods,day,received_cents}')::int=4000,'soma balcão e Pix complementares online, sem contar o dia anterior');
select pg_temp.assert((current_setting('test.snapshot')::jsonb#>>'{periods,day,paid_orders}')::int=2,'duas cobranças de um pedido contam um pedido');
select pg_temp.assert((current_setting('test.snapshot')::jsonb#>>'{periods,day,refunds_cents}')::int=2000,'devolução é descontada uma vez');
select pg_temp.assert((current_setting('test.snapshot')::jsonb#>>'{periods,day,cost_cents}')::int=200,'custos fracionários e adições preservam o custo histórico correto');
select pg_temp.assert((current_setting('test.snapshot')::jsonb#>>'{periods,day,result_cents}')::int=1500,'resultado líquido de devolução, custo e despesa');
select pg_temp.assert((current_setting('test.snapshot')::jsonb#>>'{periods,week,received_cents}')::int=4000+case when date_trunc('week',current_setting('test.reference')::date::timestamp)::date<=current_setting('test.reference')::date-1 then 500 else 0 end,'semana começa na segunda-feira');
select pg_temp.assert((current_setting('test.snapshot')::jsonb#>>'{periods,month,received_cents}')::int=4000+case when date_trunc('month',current_setting('test.reference')::date::timestamp)::date<=current_setting('test.reference')::date-1 then 500 else 0 end,'mês começa no primeiro dia');
select pg_temp.assert((current_setting('test.snapshot')::jsonb#>>'{inventory,negative_count}')::int=1,'saldo negativo aparece no dashboard');
-- Tirar a ficha para a próxima compra torna o resultado incompleto; cadastrá-la
-- depois não inventa custos retroativos para a venda feita sem ficha.
reset role;
select set_config('app.audit_reason','Mudança de ficha na fixture',true);
delete from public.recipe_items where product_id='admin-test-burger';
select pg_temp.pos_fixture('d2000000-0000-0000-0000-000000000003',1000,1,now());
insert into public.recipe_items values('admin-test-burger','d1000000-0000-0000-0000-000000000001',4);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"d0000000-0000-0000-0000-000000000001","session_id":"admin-test"}',true);
select pg_temp.assert(public.admin_control_snapshot()#>'{periods,day,result_cents}'='null'::jsonb,'ficha posterior não transforma custo desconhecido em lucro');
rollback;
\o
\echo 'Admin: imagens, RLS, PIN atômico, períodos, dois canais, custos, devoluções e histórico passaram.'
