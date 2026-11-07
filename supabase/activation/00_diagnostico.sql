-- Somente leitura: não altera banco, usuários, pagamentos ou configurações.
select
  exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='profiles' and column_name='name') as contrato_ingles,
  exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='profiles' and column_name='nome') as contrato_portugues,
  exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='profiles' and column_name='full_name') as contrato_legado,
  to_regprocedure('public.public_menu()') is not null as cardapio_015,
  to_regclass('public.online_orders') is not null as pedidos_016,
  to_regprocedure('public.online_ai_consent(text,text)') is not null as integracoes_017,
  to_regprocedure('public.admin_control_snapshot(date)') is not null as admin_018,
  (select coalesce(jsonb_agg(table_name order by table_name),'[]'::jsonb)
    from information_schema.tables where table_schema='public') as tabelas_existentes;

-- Estes indicadores não substituem o histórico de migrações nem comprovam
-- instalação integral. Nenhuma credencial ou contato de cliente é consultado.
