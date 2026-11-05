\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,msg text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'ASSERT: %',msg; end if; end $$;
create temp table estado(chave text primary key,valor jsonb);
grant all on estado to authenticated,service_role;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003'),('00000000-0000-0000-0000-000000000004');
update public.profiles set role='admin',ativo=true where id='00000000-0000-0000-0000-000000000001';
update public.profiles set role='caixa',ativo=true where id in ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004');
update public.profiles set role='cozinha',ativo=true where id='00000000-0000-0000-0000-000000000003';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
insert into public.categories(id,nome) values('10000000-0000-0000-0000-000000000001','Lanches');
insert into public.products(id,category_id,nome,preco) values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','X-Tudo',17);
insert into public.ingredients(id,nome,unidade_medida,quantidade_atual,custo_unitario) values('30000000-0000-0000-0000-000000000001','Pão','unidade',50,1);
insert into public.technical_sheets values('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',1,now(),now());
update public.integration_sources set ativo=true,user_id='00000000-0000-0000-0000-000000000001' where id='whatsapp';
insert into public.integration_sources(id,nome,ativo,user_id,scopes) values
 ('ponte','Ponte de testes',true,'00000000-0000-0000-0000-000000000001',array['orders']),
 ('entregador','Logística de testes',true,'00000000-0000-0000-0000-000000000001',array['fulfillment']),
 ('anuncios','Anúncios de testes',true,'00000000-0000-0000-0000-000000000001',array['ads']);
insert into public.integration_product_map(source_id,external_sku,product_id) values('ponte','SKU-1','20000000-0000-0000-0000-000000000001');
set local role service_role;
select set_config('request.jwt.claims','{}',true);
select public.eco_ingest_whatsapp('msg1','11999999999','Quero dois X-Tudo',now(),'Cliente de teste');
insert into estado values('job1',public.eco_claim_whatsapp());
select pg_temp.check_true((public.eco_ai_context((select valor->>'id' from estado where chave='job1'),
 (select (valor->>'lease_token')::uuid from estado where chave='job1'))->'menu'->0->>'preco')::numeric=17,'IA consulta preço atual');
insert into estado values('draft',public.eco_ai_propose('msg1',(select (valor->>'lease_token')::uuid from estado where chave='job1'),
 '[{"product_id":"20000000-0000-0000-0000-000000000001","quantidade":2,"preco_unitario":0,"modificadores":{"cebola":false}}]',
 'delivery','pix','{"logradouro":"Rua de Teste","numero":"10","bairro":"Centro"}'));
select pg_temp.check_true((select (valor->>'total')::numeric=34 from estado where chave='draft'),'rascunho ignora preço vindo da IA');
do $$ begin
  begin perform public.eco_ai_confirm('msg1',(select (valor->>'lease_token')::uuid from estado where chave='job1'));
    raise exception 'ASSERT: criou sem confirmação explícita';
  exception when raise_exception then if sqlerrm like 'ASSERT:%' then raise; end if; end;
end $$;
select public.eco_finish_whatsapp('msg1',(select (valor->>'lease_token')::uuid from estado where chave='job1'),'Resumo de teste','out1',true);
select public.eco_ingest_whatsapp('msg2','11999999999','CONFIRMAR',now()+interval '1 second','Cliente de teste');
insert into estado values('job2',public.eco_claim_whatsapp());
insert into estado values('sale',public.eco_ai_confirm('msg2',(select (valor->>'lease_token')::uuid from estado where chave='job2')));
select pg_temp.check_true(public.eco_ai_confirm('msg2',(select (valor->>'lease_token')::uuid from estado where chave='job2'))=(select valor from estado where chave='sale'),'confirmação idempotente');
select public.eco_finish_whatsapp('msg2',(select (valor->>'lease_token')::uuid from estado where chave='job2'),'Registrado, pagamento pendente','out2',true);
reset role;
insert into estado select 'customer',to_jsonb(customer_id) from planeta_private.customer_data where telefone='11999999999';
select pg_temp.check_true((select quantidade_atual=48 from public.ingredients),'replay não duplica baixa');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000003"}',true);
select pg_temp.check_true((select count(id)=0 from public.orders),'KDS não vê pedido sem pagamento');
select pg_temp.check_true((select count(id)=0 from public.order_items),'KDS não vê itens de pedido sem pagamento');
do $$ begin
  begin perform telefone from planeta_private.customer_data; raise exception 'ASSERT: cozinha leu PII';
  exception when insufficient_privilege then null; end;
  begin perform public.eco_claim_whatsapp(); raise exception 'ASSERT: cozinha chamou worker';
  exception when insufficient_privilege then null; end;
  begin perform public.eco_privacy_request(repeat('a',64),'acesso'); raise exception 'ASSERT: cozinha usou API service';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
do $$ begin
  begin insert into public.orders(customer_id,metodo_pagamento,tipo)
    values((select (valor#>>'{}')::uuid from estado where chave='customer'),'pix','balcao');
    raise exception 'ASSERT: caixa vinculou cliente histórico num pedido inventado';
  exception when insufficient_privilege then null; end;
end $$;
select public.assumir_pedido((select (valor->>'order_id')::uuid from estado where chave='sale'));
select pg_temp.check_true((select count(*)=1 from public.orders_gestao),'caixa vê pedido atribuído');
select pg_temp.check_true(public.contato_do_pedido((select (valor->>'order_id')::uuid from estado where chave='sale'))->>'telefone'='11999999999','contato pontual autorizado');
do $$ begin
  begin perform public.confirmar_pagamento((select (valor->>'order_id')::uuid from estado where chave='sale'),'pix-falso');
    raise exception 'ASSERT: caixa confirmou Pix';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000004"}',true);
do $$ begin
  begin perform public.contato_do_pedido((select (valor->>'order_id')::uuid from estado where chave='sale'));
    raise exception 'ASSERT: outro caixa leu contato';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
do $$ begin
  begin update public.orders set status='preparando' where id=(select (valor->>'order_id')::uuid from estado where chave='sale');
    raise exception 'ASSERT: preparou sem pagamento';
  exception when raise_exception then if sqlerrm like 'ASSERT:%' then raise; end if; end;
end $$;
select public.confirmar_pagamento((select (valor->>'order_id')::uuid from estado where chave='sale'),'EXTRATO-TESTE-001');
select public.confirmar_pagamento((select (valor->>'order_id')::uuid from estado where chave='sale'),'EXTRATO-TESTE-001');
do $$ begin
  begin update public.order_items set quantidade=3 where order_id=(select (valor->>'order_id')::uuid from estado where chave='sale');
    raise exception 'ASSERT: itens alterados depois do pagamento';
  exception when raise_exception then if sqlerrm like 'ASSERT:%' then raise; end if; end;
end $$;
update public.orders_gestao set logistics_source='entregador' where id=(select (valor->>'order_id')::uuid from estado where chave='sale');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000003"}',true);
select pg_temp.check_true((select count(id)=1 from public.orders),'KDS vê pedido pago');
update public.orders set status='preparando' where id=(select (valor->>'order_id')::uuid from estado where chave='sale');
update public.orders set status='pronto' where id=(select (valor->>'order_id')::uuid from estado where chave='sale');
-- Link de privacidade só é emitido para uma mensagem assinada e um lease válido.
set local role service_role;
select set_config('request.jwt.claims','{}',true);
select public.eco_ingest_whatsapp('msg3','11999999999','PRIVACIDADE',now()+interval '2 seconds','Cliente de teste');
insert into estado values('job3',public.eco_claim_whatsapp());
insert into estado values('token',to_jsonb(public.eco_privacy_link('msg3',(select (valor->>'lease_token')::uuid from estado where chave='job3'))));
select public.eco_finish_whatsapp('msg3',(select (valor->>'lease_token')::uuid from estado where chave='job3'),'Link pessoal de teste','out3',true);
insert into estado values('report',public.eco_privacy_request((select valor#>>'{}' from estado where chave='token'),'acesso'));
select pg_temp.check_true((select valor->'perfil'->>'telefone'='11999999999' and jsonb_array_length(valor->'pedidos')=1
  and jsonb_array_length(valor->'rascunhos')=1 and jsonb_array_length(valor->'solicitacoes')=1
  from estado where chave='report'),'relatório vinculado ao titular, incluindo rascunhos e histórico de solicitações');
select public.eco_privacy_request((select valor#>>'{}' from estado where chave='token'),'consentir_anuncios');
insert into estado values('forget',public.eco_privacy_request((select valor#>>'{}' from estado where chave='token'),'anonimizacao'));
select pg_temp.check_true((select valor->>'status'='pendente_pedido_em_andamento' from estado where chave='forget'),'exclusão aguarda entrega');
select public.eco_fulfillment('entregador','delivery1',(select (valor->>'order_id')::uuid from estado where chave='sale'),'despachado');
select public.eco_fulfillment('entregador','delivery2',(select (valor->>'order_id')::uuid from estado where chave='sale'),'entregue');
select public.eco_fulfillment('entregador','delivery2',(select (valor->>'order_id')::uuid from estado where chave='sale'),'entregue');
select pg_temp.check_true(public.eco_privacy_request((select valor#>>'{}' from estado where chave='token'),'anonimizacao')->>'status'='concluido','replay da exclusão mostra conclusão');
reset role;
select pg_temp.check_true((select count(*)=0 from planeta_private.customer_data),'contato apagado');
select pg_temp.check_true((select count(*)=0 from planeta_private.chat_messages),'conversas apagadas');
select pg_temp.check_true((select count(*)=0 from public.integration_outbox),'exclusão revoga anúncios antes da entrega');
select pg_temp.check_true((select sum(pontos)=34 and count(*)=1 from public.loyalty_points),'pontos automáticos uma vez por entrega');
set local role service_role;
select set_config('request.jwt.claims','{}',true);
select public.eco_ingest_whatsapp('msg1','11999999999','Replay depois da exclusão',now(),'Cliente de teste');
reset role;
select pg_temp.check_true((select count(*)=0 from planeta_private.customer_data),'replay não recria cliente esquecido');
-- Segundo cliente: inatividade + opt-in explícito, depois revogação imediata.
set local role service_role;
select set_config('request.jwt.claims','{}',true);
select public.eco_ingest_whatsapp('opt1','11888888888','quero receber promoções',now(),'Outro cliente');
reset role;
insert into estado select 'customer2',to_jsonb(customer_id) from planeta_private.customer_data where telefone='11888888888';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
-- Histórico criado pelo proprietário como fixture, não por uma conta do frontend.
reset role;
select set_config('request.jwt.claims','{}',true);
insert into public.orders(id,user_id,customer_id,metodo_pagamento,tipo,created_at) values('40000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',
 (select (valor#>>'{}')::uuid from estado where chave='customer2'),'dinheiro','balcao',now()-interval '20 days');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
insert into public.order_items(order_id,product_id,quantidade) values('40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001',1);
select public.confirmar_pagamento('40000000-0000-0000-0000-000000000002','CAIXA-TESTE-002');
update public.orders set status='preparando' where id='40000000-0000-0000-0000-000000000002';
update public.orders set status='pronto' where id='40000000-0000-0000-0000-000000000002';
update public.orders set status='entregue' where id='40000000-0000-0000-0000-000000000002';
select pg_temp.check_true((select count(*)=1 from public.clientes_inativos_15_dias),'segmentação 15 dias só opt-in');
insert into public.marketing_campaigns(id,nome,template_name) values('60000000-0000-0000-0000-000000000001','Recompra','promocao_aprovada');
select pg_temp.check_true(public.iniciar_campanha('60000000-0000-0000-0000-000000000001')=1,'campanha enfileira elegível');
set local role service_role;
select set_config('request.jwt.claims','{}',true);
insert into estado values('delivery',public.eco_claim_campaign());
select pg_temp.check_true(public.eco_campaign_allowed((select (valor->>'id')::uuid from estado where chave='delivery'),
 (select (valor->>'lease_token')::uuid from estado where chave='delivery')),'consentimento rechecado antes do envio');
select public.eco_ingest_whatsapp('opt2','11888888888','SAIR',now()+interval '1 second','Outro cliente');
select pg_temp.check_true(not public.eco_campaign_allowed((select (valor->>'id')::uuid from estado where chave='delivery'),
 (select (valor->>'lease_token')::uuid from estado where chave='delivery')),'SAIR cancela envio já reservado');
-- Ponte não confia em preço nem em informação de pagamento e deduplica eventos.
insert into estado values('external',to_jsonb(public.eco_ingest_order('ponte','event1','external1',
 '{"tipo":"balcao","metodo_pagamento":"pix","itens":[{"sku":"SKU-1","quantidade":1}]}')));
select pg_temp.check_true(to_jsonb(public.eco_ingest_order('ponte','event1','external1',
 '{"tipo":"balcao","metodo_pagamento":"pix","itens":[{"sku":"SKU-1","quantidade":1}]}'))=(select valor from estado where chave='external'),'evento não duplica venda');
do $$ begin
  begin perform public.eco_ingest_order('ponte','event1','external1',
    '{"tipo":"balcao","metodo_pagamento":"pix","itens":[{"sku":"SKU-1","quantidade":2}]}');
    raise exception 'ASSERT: evento alterado aceito';
  exception when raise_exception then if sqlerrm like 'ASSERT:%' then raise; end if; end;
  begin perform public.eco_ingest_order('ponte','event2','external2',
    '{"tipo":"balcao","metodo_pagamento":"pix","pago":true,"itens":[{"sku":"SKU-1","quantidade":1}]}');
    raise exception 'ASSERT: payload financeiro arbitrário aceito';
  exception when raise_exception then if sqlerrm like 'ASSERT:%' then raise; end if; end;
end $$;
reset role;
select pg_temp.check_true((select pagamento_status='aguardando' and total=17 from public.orders where id=(select (valor#>>'{}')::uuid from estado where chave='external')),'ponte gera total local e aguarda pagamento');
select pg_temp.check_true((select quantidade_atual=46 from public.ingredients),'consumo final sem duplicação');
select pg_temp.check_true(not exists(select 1 from public.audit_logs
 where dados_novos::text like '%11999999999%' or dados_antigos::text like '%Rua de Teste%'),'auditoria sem contato ou endereço');
set local role anon;
do $$ begin
  begin perform public.eco_ingest_whatsapp('invasao','11999999999','x',now(),'x'); raise exception 'ASSERT: anon ingressou webhook';
  exception when insufficient_privilege then null; end;
  begin perform * from public.clientes_inativos_15_dias; raise exception 'ASSERT: anon exportou segmentação';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
\echo 'Ecossistema: IA, idempotência, pagamento, fidelidade, consentimento, logística e privacidade passaram.'
