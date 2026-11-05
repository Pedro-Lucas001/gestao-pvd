\set ON_ERROR_STOP on
\o /dev/null
begin;
select set_config('app.audit_reason','Fixtures isoladas do módulo tático',true);
create function pg_temp.assert(ok boolean,msg text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'ASSERT: %',msg; end if; end $$;
insert into auth.users(id) values
 ('b0000000-0000-0000-0000-000000000001'),('b0000000-0000-0000-0000-000000000002'),
 ('b0000000-0000-0000-0000-000000000003'),('b0000000-0000-0000-0000-000000000004');
update public.profiles set role='admin',active=true where id='b0000000-0000-0000-0000-000000000001';
update public.profiles set active=true where id='b0000000-0000-0000-0000-000000000002';
update public.profiles set role='kitchen',sector='grill',active=true where id='b0000000-0000-0000-0000-000000000003';
update public.profiles set role='kitchen',sector='bar',active=true where id='b0000000-0000-0000-0000-000000000004';
insert into public.ingredients(id,name,unit,stock,unit_cost_cents) values('b1000000-0000-0000-0000-000000000001','Insumo fictício para teste','un',100,100);
select set_config('test.drink',(select id from public.products where sector='bar' and active limit 1),true);
insert into public.recipe_items(product_id,ingredient_id,quantity) values('x-tudo','b1000000-0000-0000-0000-000000000001',1),(current_setting('test.drink'),'b1000000-0000-0000-0000-000000000001',1);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b0000000-0000-0000-0000-000000000001","session_id":"admin-tactical"}',true);
select set_config('test.device',(public.register_terminal('Balcão tático','Cadastro controlado no teste')->>'token'),true);
select public.set_staff_pin('b0000000-0000-0000-0000-000000000002','1313');
select public.set_staff_pin('b0000000-0000-0000-0000-000000000003','2424');
select public.set_staff_pin('b0000000-0000-0000-0000-000000000004','3535');
do $$ begin
 begin perform public.set_staff_pin('b0000000-0000-0000-0000-000000000004','2424');raise exception 'ASSERT: PIN duplicado aceito';
 exception when raise_exception then if sqlerrm<>'staff_pin_in_use' then raise; end if; end;
 begin perform public.authenticate_staff_pin('1313',current_setting('test.device'));raise exception 'ASSERT: cliente chamou troca de PIN';
 exception when insufficient_privilege then null; end;
end $$;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.authenticate_staff_pin('9999',current_setting('test.device')) from generate_series(1,5);
select pg_temp.assert(public.authenticate_staff_pin('1313',current_setting('test.device'))->>'error'='PIN_LOCKED','5 falhas bloqueiam inclusive o PIN correto');
reset role;
select pg_temp.assert((select extract(epoch from locked_until-now())=180 from app_private.terminal_attempts),'bloqueio exato de três minutos');
update app_private.terminal_attempts set locked_until=now()-interval '1 second';
set local role service_role;
select set_config('test.proof',public.authenticate_staff_pin('1313',current_setting('test.device'))::text,true);
select pg_temp.assert((current_setting('test.proof')::jsonb->>'user_id')::uuid='b0000000-0000-0000-0000-000000000002','PIN resolve funcionário individual');
select public.bind_fastpass_session('b0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000121',current_setting('test.proof')::jsonb->>'challenge');
do $$ begin
 begin perform public.bind_fastpass_session('b0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000123',current_setting('test.proof')::jsonb->>'challenge');
 raise exception 'ASSERT: reutilizou desafio'; exception when insufficient_privilege then null; end;
end $$;
-- O desafio também fica vinculado à versão do PIN: simula troca concorrente.
select set_config('test.old_proof',public.authenticate_staff_pin('3535',current_setting('test.device'))::text,true);
reset role;
update app_private.pin_credentials set pin_hash=extensions.crypt('4646',extensions.gen_salt('bf',10))
 where user_id='b0000000-0000-0000-0000-000000000004';
set local role service_role;
do $$ begin
 begin perform public.bind_fastpass_session('b0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000124',current_setting('test.old_proof')::jsonb->>'challenge');
 raise exception 'ASSERT: desafio antigo sobreviveu à troca do PIN';exception when insufficient_privilege then null;end;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b0000000-0000-0000-0000-000000000002","session_id":"b0000000-0000-0000-0000-000000000121"}',true);
select pg_temp.assert((public.operator_context()->>'role')='cashier' and not(public.operator_context()->>'requires_password')::boolean,'contexto individual real');
select public.open_shift(0);
select set_config('test.order',(public.create_order(gen_random_uuid(),'Nome que a cozinha não pode receber','counter',jsonb_build_array(
 jsonb_build_object('product_id','x-tudo','quantity',16,'modifiers','[]'::jsonb,'notes',''),
 jsonb_build_object('product_id',current_setting('test.drink'),'quantity',3,'modifiers','[]'::jsonb,'notes','')))).id::text,true);
select pg_temp.assert(not exists(select 1 from jsonb_array_elements(public.kitchen_load_snapshot()) s where (s->>'queued_items')::int<>0),'pagamento pendente não gera carga');
select public.confirm_cash((public.begin_payment(current_setting('test.order')::uuid,'cash',gen_random_uuid())).id);
select pg_temp.assert(exists(select 1 from jsonb_array_elements(public.kitchen_load_snapshot()) s where s->>'sector'='grill' and (s->>'queued_items')::int=16),'carga conta hambúrgueres, não número de tickets');
select pg_temp.assert(exists(select 1 from jsonb_array_elements(public.kitchen_load_snapshot()) s where s->>'sector'='bar' and (s->>'queued_items')::int=3),'bebidas vão para o bar');
select pg_temp.assert(position('Nome que' in public.kitchen_load_snapshot()::text)=0 and position('customer' in public.kitchen_load_snapshot()::text)=0,'snapshot não carrega dados de clientes');
do $$ begin
 begin perform public.admin_dre(now()-interval '1 day',now()+interval '1 day');raise exception 'ASSERT: caixa acessou DRE'; exception when insufficient_privilege then null; end;
 begin update public.kitchen_station_load set queued_items=0;raise exception 'ASSERT: caixa manipulou demanda';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('test.grill',(select id::text from public.kitchen_tickets where order_id=current_setting('test.order')::uuid and sector='grill'),true);
select set_config('test.bar',(select id::text from public.kitchen_tickets where order_id=current_setting('test.order')::uuid and sector='bar'),true);
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('test.proof',public.authenticate_staff_pin('2424',current_setting('test.device'))::text,true);
select public.bind_fastpass_session('b0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000122',current_setting('test.proof')::jsonb->>'challenge');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b0000000-0000-0000-0000-000000000003","session_id":"b0000000-0000-0000-0000-000000000122"}',true);
select pg_temp.assert((select count(*)=1 and bool_and(sector='grill') from public.kitchen_tickets),'chapeiro só recebe sua praça');
select pg_temp.assert(jsonb_array_length(public.kitchen_load_snapshot())=3,'visão compartilhada contém apenas agregados das três praças');
do $$ begin
 begin perform public.update_ticket(current_setting('test.bar')::uuid,'preparing');raise exception 'ASSERT: chapeiro alterou bebidas';exception when insufficient_privilege then null;end;
 begin perform public.set_kitchen_station('bar',90,4,20,'Tentativa não autorizada');raise exception 'ASSERT: cozinha alterou configuração';exception when insufficient_privilege then null;end;
end $$;
select public.update_ticket(current_setting('test.grill')::uuid,'preparing');
select pg_temp.assert((select preparing_items=16 and queued_items=0 from public.kitchen_station_load where sector='grill'),'estado em preparo sincroniza carga');
select public.update_ticket(current_setting('test.grill')::uuid,'ready');
reset role;
update public.kitchen_tickets set started_at=now()-interval '6 minutes',ready_at=now()-interval '2 minutes' where id=current_setting('test.grill')::uuid;
select pg_temp.assert((select average_unit_seconds=15 and sample_count=1 and queued_items=0 and preparing_items=0 from public.kitchen_station_load where sector='grill'),'média ponderada de preparo por unidade');
update public.ingredients set unit_cost_cents=200 where id='b1000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b0000000-0000-0000-0000-000000000001","session_id":"admin-tactical"}',true);
select set_config('test.expense',gen_random_uuid()::text,true);
select public.record_operating_expense(current_setting('test.expense')::uuid,'Despesa fictícia',2500,current_date,'Lançamento controlado para teste');
select public.record_operating_expense(current_setting('test.expense')::uuid,'Despesa fictícia',2500,current_date,'Lançamento controlado para teste');
select set_config('test.dre',public.admin_dre(date_trunc('day',now() at time zone 'America/Recife') at time zone 'America/Recife', (date_trunc('day',now() at time zone 'America/Recife')+interval '1 day') at time zone 'America/Recife')::text,true);
select pg_temp.assert((current_setting('test.dre')::jsonb->>'expense_cents')::int=2500,'retry não duplica despesas');
select pg_temp.assert((current_setting('test.dre')::jsonb->>'cost_cents')::int=1900,'DRE usa custo capturado, não o custo alterado depois');
select pg_temp.assert((current_setting('test.dre')::jsonb->>'products_without_recipe')::int=0,'fichas completas permitem resultado');
select pg_temp.assert((select count(*)=1 from pg_publication_tables where pubname='supabase_realtime' and tablename='kitchen_station_load'),'carga publicada no Realtime');
-- Uma promoção não pode transformar a sessão fraca de PIN em login administrativo.
reset role;
update public.profiles set role='admin' where id='b0000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b0000000-0000-0000-0000-000000000002","session_id":"b0000000-0000-0000-0000-000000000121"}',true);
select pg_temp.assert((public.operator_context()->>'requires_password')::boolean,'promoção exige senha em uma nova sessão');
do $$ begin
 begin perform public.admin_dre(now()-interval '1 day',now()+interval '1 day');raise exception 'ASSERT: PIN ganhou poderes de admin';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims','{"sub":"b0000000-0000-0000-0000-000000000002","session_id":"nova-sessao-por-senha"}',true);
select pg_temp.assert(not(public.operator_context()->>'requires_password')::boolean,'nova sessão forte é distinta do Fast-Pass');
rollback;
\o
\echo 'TACTICAL OK: Fast-Pass individual, lockout, desafios únicos, promoção protegida, setores, demanda, média e DRE com custo capturado.'
