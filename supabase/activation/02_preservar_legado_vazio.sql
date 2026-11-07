-- Somente para a estrutura antiga com profiles.full_name/pin_code e price.
-- Não apaga tabelas nem dados. Recusa contas, buckets ou registros existentes.
-- Revisar o diagnóstico e as dependências antes de executar.
begin;
do $legacy_guard$
declare
  expected text[] := array['audit_logs','customers','ingredients','order_items','orders','products','profiles','technical_sheets'];
  actual text[];
  tab text;
  occupied boolean;
  fn record;
begin
  perform pg_advisory_xact_lock(638194502);
  select array_agg(table_name::text order by table_name) into actual
    from information_schema.tables where table_schema='public';
  if actual is distinct from expected
    or exists(select 1 from pg_namespace where nspname in ('app_private','planeta_legacy_20261107'))
    or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='full_name')
    or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='pin_code')
    or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='price')
    or exists(select 1 from auth.users)
    or exists(select 1 from storage.buckets)
    or exists(select 1 from pg_trigger where tgrelid='auth.users'::regclass and not tgisinternal)
  then raise exception 'LEGACY_ARCHIVE_PRECONDITION_FAILED: estrutura diferente, contas, buckets ou gatilhos Auth existentes. Nenhuma alteração autorizada por este script.';end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prorettype<>'event_trigger'::regtype
      and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')
      and p.proname not in ('deduct_stock_on_order','process_loyalty_rewards','get_inactive_customers_with_balance','anonymize_customer_data')
  ) then raise exception 'LEGACY_ARCHIVE_UNKNOWN_FUNCTION: revisar funções antes da transição';end if;
  foreach tab in array expected loop
    execute format('lock table public.%I in access exclusive mode',tab);
    execute format('select exists(select 1 from public.%I)',tab) into occupied;
    if occupied then raise exception 'LEGACY_ARCHIVE_HAS_DATA: %. Nenhum registro será descartado.',tab;end if;
  end loop;

  create schema planeta_legacy_20261107;
  comment on schema planeta_legacy_20261107 is 'Estrutura anterior preservada na ativação de 07/11/2026; acesso exclusivo de administração do banco. Não expor via Data API.';
  foreach tab in array expected loop
    execute format('alter table public.%I set schema planeta_legacy_20261107',tab);
  end loop;
  for fn in
    select p.proname,pg_get_function_identity_arguments(p.oid) args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('deduct_stock_on_order','process_loyalty_rewards','get_inactive_customers_with_balance','anonymize_customer_data')
      and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')
  loop
    execute format('alter function public.%I(%s) set schema planeta_legacy_20261107',fn.proname,fn.args);
    execute format('alter function planeta_legacy_20261107.%I(%s) set search_path to planeta_legacy_20261107,extensions',fn.proname,fn.args);
  end loop;
  revoke all on schema planeta_legacy_20261107 from public,anon,authenticated,service_role;
  revoke all on all tables in schema planeta_legacy_20261107 from public,anon,authenticated,service_role;
  revoke all on all sequences in schema planeta_legacy_20261107 from public,anon,authenticated,service_role;
  revoke all on all functions in schema planeta_legacy_20261107 from public,anon,authenticated,service_role;
end
$legacy_guard$;
commit;
