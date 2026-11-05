-- Exclusivamente no PostgreSQL DESCARTÁVEL, após sql_editor/planeta_lanches_completo.sql.
\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,msg text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'ASSERT: %',msg; end if; end $$;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000001'),
 ('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003'),
 ('00000000-0000-0000-0000-000000000004');
select pg_temp.assert_true((select not ativo and role='caixa' from public.profiles where id='00000000-0000-0000-0000-000000000001'),'signup não promove');
update public.profiles set role='admin',ativo=true,pin_code='8765' where id='00000000-0000-0000-0000-000000000001';
update public.profiles set role='caixa',ativo=true where id='00000000-0000-0000-0000-000000000002';
update public.profiles set role='cozinha',ativo=true where id='00000000-0000-0000-0000-000000000003';
update public.profiles set role='caixa',ativo=true where id='00000000-0000-0000-0000-000000000004';
select pg_temp.assert_true((select pin_code is null from public.profiles where id='00000000-0000-0000-0000-000000000001'),'PIN sem texto puro');
select pg_temp.assert_true((select pin_hash<>'8765' from planeta_private.pin_credentials where user_id='00000000-0000-0000-0000-000000000001'),'hash privado');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
insert into public.categories(id,nome) values ('10000000-0000-0000-0000-000000000001','Lanches');
insert into public.products(id,category_id,nome,preco) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','X-Tudo',17);
insert into public.ingredients(id,nome,unidade_medida,quantidade_atual,custo_unitario) values
 ('30000000-0000-0000-0000-000000000001','Pão','unidade',10,1);
insert into public.technical_sheets(product_id,ingredient_id,quantidade) values
 ('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',1);
select pg_temp.assert_true((public.verificar_pin('8765')->>'ok')::boolean,'PIN correto');
select public.verificar_pin('0000') from generate_series(1,5);
select pg_temp.assert_true(not (public.verificar_pin('8765')->>'ok')::boolean,'cinco falhas bloqueiam até PIN correto');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
insert into public.orders(id,metodo_pagamento,tipo,total) values ('40000000-0000-0000-0000-000000000001','pix','balcao',999);
insert into public.order_items(id,order_id,product_id,quantidade,preco_unitario,modificadores) values
 ('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',2,0,'{"cebola":false}');
select pg_temp.assert_true((select total=34 from public.orders_gestao where id='40000000-0000-0000-0000-000000000001'),'total e preço calculados');
select pg_temp.assert_true((select count(*)=0 from public.ingredients),'caixa não acessa estoque');
select pg_temp.assert_true((select count(*)=0 from public.audit_logs),'caixa não acessa auditoria');
delete from public.orders where id='40000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select count(*)=1 from public.orders),'caixa não exclui');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000004"}',true);
select pg_temp.assert_true((select count(*)=0 from public.orders_gestao),'outro caixa não vê pedido');
do $$ begin
  begin
    insert into public.order_items(order_id,product_id,quantidade) values
    ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',1);
    raise exception 'ASSERT: outro caixa inseriu item';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000003"}',true);
select pg_temp.assert_true((select count(id)=1 from public.orders),'cozinha vê campos seguros');
select pg_temp.assert_true((select count(*)=0 from public.orders_gestao),'cozinha não vê pagamentos na view');
select pg_temp.assert_true((select count(id)=1 from public.order_items),'KDS vê os itens sem preço');
select pg_temp.assert_true((select count(*)=0 from public.order_items_gestao),'KDS sem view financeira de itens');
do $$ begin
  begin perform preco_unitario from public.order_items; raise exception 'ASSERT: cozinha leu preço';
  exception when insufficient_privilege then null; end;
  begin perform total from public.orders; raise exception 'ASSERT: cozinha leu total';
  exception when insufficient_privilege then null; end;
  begin
    update public.orders set metodo_pagamento='pix' where id='40000000-0000-0000-0000-000000000001';
    raise exception 'ASSERT: cozinha sondou método atual com update sem mudança';
  exception when insufficient_privilege then null; end;
  begin
    update public.orders set metodo_pagamento='dinheiro' where id='40000000-0000-0000-0000-000000000001';
    raise exception 'ASSERT: cozinha alterou pagamento';
  exception when insufficient_privilege then null; end;
  begin insert into public.orders(metodo_pagamento,tipo) values('pix','balcao');
    raise exception 'ASSERT: cozinha inseriu pedido';
  exception when insufficient_privilege then null; end;
end $$;
update public.orders set status='preparando' where id='40000000-0000-0000-0000-000000000001';
update public.orders set status='pronto' where id='40000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
update public.orders_gestao set tipo='delivery' where id='40000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select tipo='delivery' from public.orders_gestao where id='40000000-0000-0000-0000-000000000001'),'admin edita pela view protegida');
select pg_temp.assert_true((select quantidade_atual=8 from public.ingredients),'baixa dois pães');
-- Uma ficha alterada não muda a devolução de consumo já registrado.
update public.technical_sheets set quantidade=3;
update public.orders set status='cancelado' where id='40000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select quantidade_atual=10 from public.ingredients),'cancelamento devolve snapshot antigo');
select pg_temp.assert_true((select count(*)=1 from public.audit_logs where acao='PEDIDO_CANCELADO'),'cancelamento auditado uma vez');
insert into public.orders(id,metodo_pagamento,tipo) values ('40000000-0000-0000-0000-000000000002','dinheiro','balcao');
insert into public.order_items(id,order_id,product_id,quantidade) values
 ('50000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001',2);
select pg_temp.assert_true((select quantidade_atual=4 from public.ingredients),'nova ficha aplicada');
update public.order_items set quantidade=1 where id='50000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select quantidade_atual=7 from public.ingredients),'editar item reconcilia estoque');
select pg_temp.assert_true((select total=17 from public.orders_gestao where id='40000000-0000-0000-0000-000000000002'),'editar item recalcula total');
do $$ begin
  begin
    insert into public.order_items(order_id,product_id,quantidade) values
    ('40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001',4);
    raise exception 'ASSERT: estoque negativo permitido';
  exception when check_violation then null; end;
end $$;
select pg_temp.assert_true((select quantidade_atual=7 from public.ingredients),'falta de estoque não deixa baixa parcial');
delete from public.orders where id='40000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select quantidade_atual=10 from public.ingredients),'excluir rascunho devolve estoque');
update public.products set descricao='Atualizado';
select pg_temp.assert_true((select updated_at>created_at from public.products limit 1),'updated_at avança após alteração');
do $$ begin
  begin update public.audit_logs set acao='forjado'; raise exception 'ASSERT: audit update';
  exception when insufficient_privilege then null; end;
  begin delete from public.audit_logs; raise exception 'ASSERT: audit delete';
  exception when insufficient_privilege then null; end;
  begin insert into public.audit_logs(acao,tabela_afetada) values('forjado','orders'); raise exception 'ASSERT: audit insert direto';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin perform id from public.orders; raise exception 'ASSERT: anônimo leu pedidos';
  exception when insufficient_privilege then null; end;
  begin perform * from public.orders_gestao; raise exception 'ASSERT: anônimo leu view';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
-- A proteção também intercepta DML do proprietário, não só usuários da API.
do $$ begin
  begin update public.audit_logs set acao='forjado'; raise exception 'ASSERT: owner audit update';
  exception when insufficient_privilege then null; end;
  begin truncate public.audit_logs; raise exception 'ASSERT: owner audit truncate';
  exception when insufficient_privilege then null; end;
end $$;
select pg_temp.assert_true((select count(*)=2 from pg_publication_tables where pubname='supabase_realtime' and tablename in ('orders','order_items')),'duas tabelas no realtime');
select pg_temp.assert_true((select not ('total'=any(attnames)) from pg_publication_tables where pubname='supabase_realtime' and tablename='orders'),'realtime sem total');
select pg_temp.assert_true((select not ('preco_unitario'=any(attnames)) from pg_publication_tables where pubname='supabase_realtime' and tablename='order_items'),'realtime sem preço');
rollback;
\echo 'SQL Editor migration: todos os testes passaram.'
