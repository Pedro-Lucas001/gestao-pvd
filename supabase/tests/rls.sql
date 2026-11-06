\set ON_ERROR_STOP on
\o /dev/null
begin;
select set_config('app.audit_reason','Preparação controlada de fixtures de teste',true);
create function pg_temp.assert(ok boolean,message text) returns void language plpgsql as $$ begin if ok is not true then raise exception 'ASSERTION FAILED: %',message; end if; end $$;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003'),('00000000-0000-0000-0000-000000000004'),
 ('00000000-0000-0000-0000-000000000005'),('00000000-0000-0000-0000-000000000006');
update public.profiles set role='admin',active=true where id='00000000-0000-0000-0000-000000000001';
update public.profiles set active=true where id in ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003');
update public.profiles set role='kitchen',sector='grill',active=true where id='00000000-0000-0000-0000-000000000004';
update public.profiles set role='kitchen',sector='bar',active=true where id='00000000-0000-0000-0000-000000000005';
insert into public.ingredients(id,name,unit,stock,unit_cost_cents) values
 ('10000000-0000-0000-0000-000000000001','Pão','un',100,100),
 ('10000000-0000-0000-0000-000000000002','Hambúrguer','un',100,200),
 ('10000000-0000-0000-0000-000000000003','Queijo','un',100,100),
 ('10000000-0000-0000-0000-000000000004','Milho','g',1000,1);
insert into public.recipe_items values
 ('x-tudo','10000000-0000-0000-0000-000000000001',1),
 ('x-tudo','10000000-0000-0000-0000-000000000002',1),
 ('x-tudo','10000000-0000-0000-0000-000000000003',1),
 ('x-tudo','10000000-0000-0000-0000-000000000004',20);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","session_id":"admin-session"}',true);
select set_config('test.device',(public.register_terminal('Terminal de testes','Cadastro controlado para testes')->>'token'),true);
select public.set_staff_pin('00000000-0000-0000-0000-000000000004','1010');
select public.set_staff_pin('00000000-0000-0000-0000-000000000005','2020');
select public.set_staff_pin('00000000-0000-0000-0000-000000000002','1234');
select public.set_staff_pin('00000000-0000-0000-0000-000000000003','5678');
do $$begin
 begin perform public.manage_staff('00000000-0000-0000-0000-000000000001','cashier',null,true,'Teste de proteção do último administrador');raise exception 'last admin must survive';exception when others then if sqlerrm<>'last_admin' then raise;end if;end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","session_id":"cashier-session"}',true);
do $$begin
 begin perform public.open_shift(0);raise exception 'locked terminal operated';exception when insufficient_privilege then null;end;
 begin update public.profiles set role='admin' where id=auth.uid();raise exception 'self promotion allowed';exception when insufficient_privilege then null;end;
 begin perform public.set_staff_pin(auth.uid(),'9999');raise exception 'self PIN reset allowed';exception when insufficient_privilege then null;end;
 begin perform public.confirm_provider_payment(gen_random_uuid(),1,'r','p','e','h');raise exception 'cashier confirmed a provider payment';exception when insufficient_privilege then null;end;
 begin perform 1 from app_private.pin_credentials;raise exception 'PIN hashes leaked';exception when insufficient_privilege then null;end;
end $$;
select pg_temp.assert((public.unlock_terminal(null,current_setting('test.device'))->>'ok')::boolean=false,'NULL PIN fails closed');
select public.unlock_terminal('0000',current_setting('test.device')) from generate_series(1,4);
select pg_temp.assert((public.unlock_terminal('1234',current_setting('test.device'))->>'ok')::boolean=false,'PIN rate limit enforced');
reset role;
update app_private.pin_credentials set failures=0,locked_until=null;
update app_private.terminal_attempts set failures=0,locked_until=null;
set local role authenticated;
select pg_temp.assert((public.unlock_terminal('1234',current_setting('test.device'))->>'ok')::boolean,'correct PIN unlocks session');
select pg_temp.assert((select count(*) from public.ingredients)=0,'cashier cannot read ingredient costs');
do $$begin begin update public.products set price_cents=1 where id='x-tudo';exception when insufficient_privilege then null;end;end $$;
select pg_temp.assert((select price_cents from public.products where id='x-tudo')=1700,'cashier cannot edit prices');
select set_config('test.shift',public.open_shift(10000)::text,true);
select pg_temp.assert(public.open_shift(10000)=current_setting('test.shift')::uuid,'opening shift retry returns same shift');
select set_config('test.order',(public.create_order('20000000-0000-0000-0000-000000000001','Mesa 4','counter','[{"product_id":"x-tudo","quantity":1,"price_cents":1,"modifiers":["Sem cebola","Ponto: ao ponto"]},{"product_id":"agua","quantity":1}]')).id::text,true);
select pg_temp.assert((select total_cents from public.orders where id=current_setting('test.order')::uuid)=1900,'server ignores client supplied prices');
select pg_temp.assert((public.create_order('20000000-0000-0000-0000-000000000001','Mesa 4','counter','[{"product_id":"x-tudo","quantity":1,"price_cents":1,"modifiers":["Sem cebola","Ponto: ao ponto"]},{"product_id":"agua","quantity":1}]')).id=current_setting('test.order')::uuid,'order retry is idempotent');
do $$begin
 begin perform public.create_order('20000000-0000-0000-0000-000000000001','Outro','counter','[{"product_id":"x-tudo","quantity":1}]');raise exception 'conflicting order accepted';exception when others then if sqlerrm<>'idempotency_conflict' then raise;end if;end;
 begin perform public.create_order(gen_random_uuid(),'Mesa','counter','[{"product_id":"x-tudo","quantity":1,"modifiers":["Ponto: ao ponto","Ponto: mal passado"]}]');raise exception 'conflicting modifier accepted';exception when others then if sqlerrm<>'conflicting_modifiers' then raise;end if;end;
 begin insert into public.orders(cashier_id,customer,channel,total_cents) values(auth.uid(),'Fraude','counter',1);raise exception 'direct insert allowed';exception when insufficient_privilege then null;end;
end $$;
-- Kitchen cannot see any unpaid ticket, or any financial table at any time.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000004","session_id":"grill-session"}',true);
select public.unlock_terminal('1010',current_setting('test.device'));
select pg_temp.assert((select count(*) from public.kitchen_tickets)=0,'unpaid order never reaches kitchen');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","session_id":"cashier-session"}',true);
select set_config('test.attempt',(public.begin_payment(current_setting('test.order')::uuid,'cash','30000000-0000-0000-0000-000000000001')).id::text,true);
select public.confirm_cash(current_setting('test.attempt')::uuid);
select public.confirm_cash(current_setting('test.attempt')::uuid);
reset role;
select pg_temp.assert((select stock from public.ingredients where name='Pão')=99,'stock deducted once');
select pg_temp.assert((select stock from public.ingredients where name='Milho')=980,'recipe units deducted');
select pg_temp.assert((select count(*) from public.stock_movements)=4,'one movement per ingredient');
select pg_temp.assert((select count(*) from public.kitchen_tickets)=2,'separate tickets per sector');
select set_config('test.bar_ticket',(select id::text from public.kitchen_tickets where sector='bar'),true);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000003","session_id":"cashier-two"}',true);
select public.unlock_terminal('5678',current_setting('test.device'));
select pg_temp.assert((select count(*) from public.orders)=0,'cashier cannot see other cashier orders');
select pg_temp.assert((select count(*) from public.shifts)=0,'cashier cannot see other shifts');
select pg_temp.assert((select count(*) from public.payment_attempts)=0,'cashier cannot see other payments');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000004","session_id":"grill-session"}',true);
select pg_temp.assert((select count(*) from public.orders)=0,'kitchen cannot read financial order rows');
select pg_temp.assert((select count(*) from public.payment_attempts)=0,'kitchen cannot read payments');
select pg_temp.assert((select count(*) from public.ingredients)=0,'kitchen cannot read costs');
select pg_temp.assert((select count(*) from public.products)=0,'kitchen cannot read catalog prices');
select pg_temp.assert((select count(*) from public.kitchen_tickets)=1,'grill sees only own sector');
select pg_temp.assert(not exists(select 1 from public.kitchen_tickets, jsonb_array_elements(items) item where item ? 'price_cents' or item ? 'unit_price_cents'),'tickets have no prices');
do $$begin
 begin perform public.update_ticket(current_setting('test.bar_ticket')::uuid,'preparing');raise exception 'cross sector mutation allowed';exception when insufficient_privilege then null;end;
end $$;
select public.update_ticket((select id from public.kitchen_tickets limit 1),'preparing');
select public.update_ticket((select id from public.kitchen_tickets limit 1),'ready');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000005","session_id":"bar-session"}',true);
select public.unlock_terminal('2020',current_setting('test.device'));
select public.update_ticket(current_setting('test.bar_ticket')::uuid,'preparing');
select public.update_ticket(current_setting('test.bar_ticket')::uuid,'ready');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","session_id":"cashier-session"}',true);
select pg_temp.assert((select status from public.orders where id=current_setting('test.order')::uuid)='ready','all sectors ready -> order ready');
select public.complete_order(current_setting('test.order')::uuid);
select public.complete_order(current_setting('test.order')::uuid);
select set_config('test.pixorder',(public.create_order('20000000-0000-0000-0000-000000000002','Pix teste','counter','[{"product_id":"agua","quantity":1}]')).id::text,true);
select set_config('test.pixattempt',(public.begin_payment(current_setting('test.pixorder')::uuid,'pix','30000000-0000-0000-0000-000000000002')).id::text,true);
set local role service_role;
do $$begin
 begin perform public.confirm_provider_payment(current_setting('test.pixattempt')::uuid,1,'ref1','fixture','event1','hash1');raise exception 'wrong amount accepted';exception when others then if sqlerrm<>'invalid_provider_payment' then raise;end if;end;
 begin perform public.confirm_provider_payment(current_setting('test.pixattempt')::uuid,null,'ref1','fixture','event1','hash1');raise exception 'NULL amount accepted';exception when others then if sqlerrm<>'invalid_provider_payment' then raise;end if;end;
end $$;
select public.confirm_provider_payment(current_setting('test.pixattempt')::uuid,200,'ref1','fixture','event1','hash1');
select public.confirm_provider_payment(current_setting('test.pixattempt')::uuid,200,'ref1','fixture','event1','hash1');
do $$begin
 begin perform public.confirm_provider_payment(current_setting('test.pixattempt')::uuid,200,'ref1','fixture','event1','otherhash');raise exception 'replayed event changed accepted';exception when others then if sqlerrm<>'event_conflict' then raise;end if;end;
end $$;
reset role;
select pg_temp.assert((select count(*) from public.payment_attempts where order_id=current_setting('test.pixorder')::uuid and status='confirmed')=1,'provider confirmation idempotent');
select pg_temp.assert((select count(*) from public.kitchen_tickets where order_id=current_setting('test.pixorder')::uuid)=1,'provider payment creates a single ticket');
set local role authenticated;
select public.close_shift(current_setting('test.shift')::uuid,11900,'Fechamento conferido no teste');
select public.close_shift(current_setting('test.shift')::uuid,11900,'Fechamento conferido no teste');
select public.lock_terminal();
select pg_temp.assert((select count(*) from public.orders)=0,'locked terminal loses DB read access');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000006","session_id":"inactive"}',true);
select pg_temp.assert((select count(*) from public.products)=0,'inactive profile cannot read menu');
set local role anon;
do $$begin
 begin perform count(*) from public.orders;raise exception 'anonymous orders allowed';exception when insufficient_privilege then null;end;
 begin perform public.open_shift(0);raise exception 'anonymous function allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
\o
\echo 'RLS OK: privilege escalation, PIN, session leases, cross-cashier isolation, prices, idempotency, payment gate, recipes, sector routing, completion and anonymous access.'
