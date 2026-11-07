\set ON_ERROR_STOP on
\o /dev/null
begin;
select set_config('app.audit_reason','Fixtures isoladas dos pedidos online',true);
create function pg_temp.assert(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'ASSERT: %',msg;end if;end $$;
insert into auth.users(id) values('c0000000-0000-0000-0000-000000000001'),('c0000000-0000-0000-0000-000000000002'),('c0000000-0000-0000-0000-000000000003'),('c0000000-0000-0000-0000-000000000004');
update public.profiles set role='admin',active=true where id='c0000000-0000-0000-0000-000000000001';
update public.profiles set role='kitchen',sector='grill',active=true where id='c0000000-0000-0000-0000-000000000002';
update public.profiles set role='kitchen',sector='bar',active=true where id='c0000000-0000-0000-0000-000000000003';
update public.profiles set role='cashier',active=true where id='c0000000-0000-0000-0000-000000000004';
insert into public.terminals(id,name) values('c1000000-0000-0000-0000-000000000001','Terminal online de teste');
insert into app_private.terminal_leases(user_id,session_id,expires_at,terminal_id) select id,'online-test',now()+interval '10 minutes','c1000000-0000-0000-0000-000000000001' from public.profiles where id in('c0000000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-000000000003','c0000000-0000-0000-0000-000000000004');
insert into public.products(id,name,category,price_cents,sector,allowed_modifiers) values('test-online-burger','Burger teste','hamburgueres',1000,'grill',array['Sem cebola']),('test-online-drink','Bebida teste','bebidas',500,'bar','{}');
insert into public.ingredients(id,name,unit,stock,unit_cost_cents) values('c2000000-0000-0000-0000-000000000001','Insumo online teste','un',100,100);
insert into public.recipe_items values('test-online-burger','c2000000-0000-0000-0000-000000000001',1);
select set_config('test.items','[{"product_id":"test-online-burger","quantity":1,"unit_price_cents":1},{"product_id":"test-online-burger","quantity":1,"modifiers":["Sem cebola"]},{"product_id":"test-online-drink","quantity":1}]',true);
select set_config('test.contact','{"name":"Cliente confidencial","phone":"5581999999999","email":"fixture@example.test","address":"Rua confidencial 123","whatsapp_consent":true}',true);
set local role anon;
do $$begin
 begin perform public.online_order_status(repeat('a',64));raise exception 'ASSERT: visitante leu RPC privado';exception when insufficient_privilege then null;end;
 begin perform public.online_quote(current_setting('test.items')::jsonb,'pickup');raise exception 'ASSERT: visitante contornou Edge';exception when insufficient_privilege then null;end;
 begin select * from public.online_orders;raise exception 'ASSERT: visitante leu tabela';exception when insufficient_privilege then null;end;
end $$;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.assert((public.online_quote(current_setting('test.items')::jsonb,'pickup')->>'total_cents')::int=2500,'preço exclusivamente canônico');
select set_config('test.order',(public.online_create_order('c3000000-0000-0000-0000-000000000001',repeat('a',64),current_setting('test.items')::jsonb,current_setting('test.contact')::jsonb,'pickup','pix',null,2500)->>'id'),true);
select pg_temp.assert(public.online_create_order('c3000000-0000-0000-0000-000000000001',repeat('a',64),current_setting('test.items')::jsonb,current_setting('test.contact')::jsonb,'pickup','pix',null,2500)->>'id'=current_setting('test.order'),'retry não duplica pedido');
do $$begin
 begin perform public.online_order_status(repeat('b',64));raise exception 'ASSERT: token errado aceito';exception when insufficient_privilege then null;end;
 begin perform public.online_create_order('c3000000-0000-0000-0000-000000000001',repeat('a',64),current_setting('test.items')::jsonb,current_setting('test.contact')::jsonb,'pickup','cash',null,2500);raise exception 'ASSERT: chave reutilizada';exception when raise_exception then if sqlerrm<>'idempotency_conflict' then raise;end if;end;
end $$;
select pg_temp.assert(position('Cliente confidencial' in public.online_order_status(repeat('a',64))::text)=0,'acompanhamento não revela contato');
select public.online_prepare_payment(repeat('a',64),'c4000000-0000-0000-0000-000000000001');
select public.online_confirm_payment('c4000000-0000-0000-0000-000000000001',2500,'mp:test1','mercadopago','event1','hash1');
select public.online_confirm_payment('c4000000-0000-0000-0000-000000000001',2500,'mp:test1','mercadopago','event1','hash1');
select pg_temp.assert((public.online_order_status(repeat('a',64))->>'paid_cents')::int=2500,'webhook duplicado não duplica recebimento');
reset role;
select pg_temp.assert((select stock=98 from public.ingredients where id='c2000000-0000-0000-0000-000000000001'),'duas linhas do mesmo produto baixam dois insumos');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"c0000000-0000-0000-0000-000000000002","session_id":"online-test"}',true);
select pg_temp.assert(jsonb_array_length(public.online_kitchen_queue()->'orders')=1 and position('unit_price' in public.online_kitchen_queue()::text)=0 and position('Cliente confidencial' in public.online_kitchen_queue()::text)=0,'cozinha só recebe seu setor, sem dinheiro nem contato');
do $$begin
 begin perform public.online_kitchen_work(current_setting('test.order')::uuid,'bar',1,'preparing');raise exception 'ASSERT: cozinha alterou outro setor';exception when insufficient_privilege then null;end;
 begin perform public.online_admin_metrics();raise exception 'ASSERT: cozinha acessou finanças';exception when insufficient_privilege then null;end;
end $$;
select public.online_kitchen_work(current_setting('test.order')::uuid,'grill',1,'preparing');
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('test.revised','[{"product_id":"test-online-burger","quantity":2},{"product_id":"test-online-burger","quantity":1,"modifiers":["Sem cebola"]},{"product_id":"test-online-drink","quantity":1}]',true);
select public.online_request_change(repeat('a',64),'c5000000-0000-0000-0000-000000000001',current_setting('test.revised')::jsonb,'Adicionar um burger',3500);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"c0000000-0000-0000-0000-000000000002","session_id":"online-test"}',true);
select public.online_review_change('c5000000-0000-0000-0000-000000000001',true,'Chapa confirmou viabilidade');
reset role;
select pg_temp.assert((select revision=1 from public.online_orders where id=current_setting('test.order')::uuid),'aprovação parcial não altera pedido');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"c0000000-0000-0000-0000-000000000003","session_id":"online-test"}',true);
select public.online_review_change('c5000000-0000-0000-0000-000000000001',true,'Bar confirmou viabilidade');
reset role;
select pg_temp.assert((select status='payment_pending' and total_cents=3500 and paid_cents=2500 and revision=2 from public.online_orders where id=current_setting('test.order')::uuid),'alteração paga antes exige diferença em Pix e pausa preparo');
select pg_temp.assert((select stock=98 from public.ingredients where id='c2000000-0000-0000-0000-000000000001'),'não baixa adição antes de receber diferença');
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.online_prepare_payment(repeat('a',64),'c4000000-0000-0000-0000-000000000002');
do $$begin
 begin perform public.online_confirm_payment('c4000000-0000-0000-0000-000000000002',1,'mp:test2','mercadopago','event2','hash2');raise exception 'ASSERT: valor menor confirmado';exception when raise_exception then if sqlerrm<>'invalid_provider_payment' then raise;end if;end;
end $$;
select public.online_confirm_payment('c4000000-0000-0000-0000-000000000002',1000,'mp:test2','mercadopago','event2','hash2');
reset role;
select pg_temp.assert((select stock=97 from public.ingredients where id='c2000000-0000-0000-0000-000000000001'),'somente diferença de insumos baixada');
-- Caixa precisa assumir e aceitar dinheiro, sem marcar como pago.
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('test.cash',(public.online_create_order('c3000000-0000-0000-0000-000000000002',repeat('b',64),'[{"product_id":"test-online-burger","quantity":1}]',current_setting('test.contact')::jsonb,'pickup','cash',2000,1000)->>'id'),true);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"c0000000-0000-0000-0000-000000000004","session_id":"online-test"}',true);
select set_config('test.shift',public.open_shift(0)::text,true);
select public.online_claim_order(current_setting('test.cash')::uuid);
select public.online_accept_cash(current_setting('test.cash')::uuid,'Loja aceita pagamento em dinheiro');
do $$begin
 begin perform public.close_shift(current_setting('test.shift')::uuid,0,'Fechamento com pendência');raise exception 'ASSERT: fechou turno com dinheiro a receber';exception when raise_exception then if sqlerrm<>'pending_orders_in_shift' then raise;end if;end;
end $$;
reset role;
select pg_temp.assert((select paid_cents=0 and status='accepted' from public.online_orders where id=current_setting('test.cash')::uuid),'aceite de dinheiro libera mas não confirma recebimento');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"c0000000-0000-0000-0000-000000000004","session_id":"online-test"}',true);
select public.online_collect_cash(current_setting('test.cash')::uuid,'c4000000-0000-0000-0000-000000000003',2000);
select public.online_collect_cash(current_setting('test.cash')::uuid,'c4000000-0000-0000-0000-000000000003',2000);
select pg_temp.assert((public.cash_summary(current_setting('test.shift')::uuid)->>'expected_cents')::int=1000,'troco não vira receita; retry não duplica caixa');
reset role;
rollback;
\o
\echo 'Pedidos online: preços, tokens, RLS, setores, alterações, estoque, Pix e dinheiro passaram.'
