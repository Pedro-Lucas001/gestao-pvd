\set ON_ERROR_STOP on
begin;
do $$begin
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('public','app_private') and c.relkind in ('r','p')
      and not c.relrowsecurity
  ) then raise exception 'Application table without row level security';end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f'
      and has_function_privilege('anon',p.oid,'execute')
      and p.proname not in ('public_menu','checkout_menu','checkout_order','checkout_status','online_shop_config')
  ) then raise exception 'Anonymous role can execute an internal RPC';end if;
  if not has_function_privilege('authenticated','public.adjust_stock(uuid,numeric,text,uuid)','execute')
    or not has_function_privilege('authenticated','public.admin_control_snapshot(date)','execute')
    or not has_function_privilege('service_role','public.confirm_provider_payment(uuid,int,text,text,text,text)','execute')
    or has_function_privilege('authenticated','public.confirm_provider_payment(uuid,int,text,text,text,text)','execute')
  then raise exception 'Explicit operator/service grants changed';end if;
end $$;
create function public.activation_rpc_probe() returns integer language sql as $$select 1$$;
do $$begin
  if has_function_privilege('anon','public.activation_rpc_probe()','execute')
    or has_function_privilege('authenticated','public.activation_rpc_probe()','execute')
  then raise exception 'A future function inherited public execution';end if;
end $$;
set local role anon;
select jsonb_array_length(public.public_menu());
do $$begin
  begin perform public.admin_metrics(now()-interval '1 day',now());
    raise exception 'Anonymous role entered administrative RPC';
  exception when insufficient_privilege then null;end;
end $$;
rollback;
