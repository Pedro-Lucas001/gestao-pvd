begin;

create table app_private.admin_security_settings (
  singleton boolean primary key default true check (singleton),
  require_mfa boolean not null default false
);
insert into app_private.admin_security_settings default values;
alter table app_private.admin_security_settings enable row level security;
revoke all on app_private.admin_security_settings from public, anon, authenticated, service_role;

create function app_private.admin_mfa_enrolled() returns boolean
language sql stable set search_path='' as $$
  select exists (
    select 1 from auth.mfa_factors
    where user_id=auth.uid() and status='verified' and factor_type='totp'
  )
$$;

create function app_private.admin_mfa_verified() returns boolean
language sql stable set search_path='' as $$
  select coalesce(auth.jwt()->>'aal'='aal2', false)
    and exists (
      select 1 from auth.sessions s join auth.mfa_factors f on f.id=s.factor_id
      where s.user_id=auth.uid()
        and s.id::text=auth.jwt()->>'session_id'
        and s.aal='aal2'
        and (s.not_after is null or s.not_after>now())
        and f.user_id=s.user_id and f.status='verified' and f.factor_type='totp'
    )
$$;

create function app_private.admin_mfa_pending() returns boolean
language sql stable set search_path='' as $$
  select (coalesce((select require_mfa from app_private.admin_security_settings where singleton), true)
    or app_private.admin_mfa_enrolled())
    and not app_private.admin_mfa_verified()
$$;

revoke all on function app_private.admin_mfa_enrolled(), app_private.admin_mfa_verified(),
  app_private.admin_mfa_pending() from public, anon, authenticated, service_role;

create or replace function app_private.role() returns public.app_role
language sql stable security definer set search_path='' as $$
  select p.role from public.profiles p
  where p.id=auth.uid() and p.active
    and case when p.role='admin' then
      not exists (
        select 1 from app_private.fastpass_sessions s
        where s.user_id=p.id and s.session_id=auth.jwt()->>'session_id'
      ) and not app_private.admin_mfa_pending()
    else true end
$$;

-- Existing privileged Edge Functions already reject a non-admin role here.
create or replace function public.operator_context() returns jsonb
language sql stable security definer set search_path='' as $$
  select to_jsonb(p) || jsonb_build_object(
    'role', case when p.role='admin' then app_private.role() else p.role end,
    'requires_password', p.role='admin' and exists (
      select 1 from app_private.fastpass_sessions s
      where s.user_id=p.id and s.session_id=auth.jwt()->>'session_id'
    ),
    'requires_mfa', p.role='admin' and p.active and app_private.admin_mfa_pending(),
    'admin_mfa_enforced', p.role='admin' and p.active and
      (select require_mfa from app_private.admin_security_settings where singleton)
  )
  from public.profiles p where p.id=auth.uid()
$$;

create function public.enable_admin_mfa() returns void
language plpgsql security definer set search_path='' as $$
begin
  if not app_private.is_admin() or not app_private.admin_mfa_verified() then
    raise exception 'access_denied' using errcode='42501';
  end if;

  update app_private.admin_security_settings set require_mfa=true
  where singleton and not require_mfa;
  if found then
    perform app_private.reason('Exigência de segundo fator ativada pela administração');
    perform app_private.log('security.admin_mfa_enabled','settings','admin_mfa');
  end if;
end
$$;
revoke all on function public.enable_admin_mfa() from public, anon, authenticated, service_role;
grant execute on function public.enable_admin_mfa() to authenticated;
notify pgrst, 'reload schema';

commit;
