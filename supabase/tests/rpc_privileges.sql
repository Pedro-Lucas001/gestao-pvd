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
reset role;

-- Model JWT claims and the private Auth state independently. A stale claim
-- cannot replace a live second-factor session.
insert into auth.users(id) values
  ('a2000000-0000-0000-0000-000000000001'),
  ('a2000000-0000-0000-0000-000000000002'),
  ('a2000000-0000-0000-0000-000000000005');
select app_private.reason('Configuração de perfis para teste de segundo fator');
update public.profiles set role='admin', active=true
where id in ('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005');
update public.profiles set active=true
where id='a2000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a2000000-0000-0000-0000-000000000001","session_id":"a2000000-0000-0000-0000-000000000010","aal":"aal1"}',true);
do $$begin
  if not app_private.is_admin() then raise exception 'Bootstrap admin was locked out'; end if;
  begin perform public.enable_admin_mfa(); raise exception 'Unverified admin enabled MFA';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into auth.mfa_factors values
  ('a2000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000001','verified','totp');
insert into auth.sessions values
  ('a2000000-0000-0000-0000-000000000010','a2000000-0000-0000-0000-000000000001','aal2',null,'a2000000-0000-0000-0000-000000000003');
set local role authenticated;
do $$begin
  if app_private.is_admin() or public.operator_context()->>'role' is not null
    or public.operator_context()->>'requires_mfa' is distinct from 'true'
  then raise exception 'Password-only session retained admin authority'; end if;
  begin perform public.admin_control_snapshot(current_date); raise exception 'Unverified admin read management reports';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"a2000000-0000-0000-0000-000000000001","session_id":"a2000000-0000-0000-0000-000000000010","aal":"aal2"}',true);
do $$begin
  if not app_private.is_admin() or public.operator_context()->>'role' is distinct from 'admin'
  then raise exception 'Verified administrator was blocked'; end if;
  perform public.admin_control_snapshot(current_date);
  perform public.enable_admin_mfa();
  perform public.enable_admin_mfa();
  if public.operator_context()->>'admin_mfa_enforced' is distinct from 'true'
  then raise exception 'MFA policy was not activated'; end if;
end $$;
reset role;
insert into auth.mfa_factors values
  ('a2000000-0000-0000-0000-000000000004','a2000000-0000-0000-0000-000000000001','verified','totp');
delete from auth.mfa_factors where id='a2000000-0000-0000-0000-000000000003';
set local role authenticated;
do $$begin
  if app_private.is_admin()
  then raise exception 'A different factor kept a revoked factor session valid'; end if;
end $$;
reset role;
update auth.sessions set factor_id='a2000000-0000-0000-0000-000000000004'
where id='a2000000-0000-0000-0000-000000000010';
delete from auth.sessions where id='a2000000-0000-0000-0000-000000000010';
set local role authenticated;
do $$begin
  if app_private.is_admin() then raise exception 'Revoked AAL2 session retained admin authority'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"a2000000-0000-0000-0000-000000000005","session_id":"unenrolled-admin","aal":"aal1"}',true);
do $$begin
  if app_private.is_admin() or public.operator_context()->>'requires_mfa' is distinct from 'true'
  then raise exception 'Unenrolled administrator bypassed MFA policy'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"a2000000-0000-0000-0000-000000000002","session_id":"staff-test","aal":"aal1"}',true);
do $$begin
  if app_private.role() is distinct from 'cashier' or public.operator_context()->>'requires_mfa' is distinct from 'false'
  then raise exception 'MFA policy changed the cashier access flow'; end if;
  begin perform public.enable_admin_mfa(); raise exception 'Cashier changed admin MFA policy';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
