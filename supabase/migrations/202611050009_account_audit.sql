begin;
create function app_private.audit_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  perform app_private.reason('Nova conta inativa criada pelo serviço de autenticação');
  perform app_private.log('profile.created','profile',new.id::text);
 elsif (old.role,old.active,old.sector) is distinct from (new.role,new.active,new.sector) then
  perform app_private.log('profile.access_changed','profile',new.id::text);
 end if;return new;
end $$;
create trigger profile_audit after insert or update on public.profiles for each row execute function app_private.audit_profile();
create or replace function public.manage_staff(p_user uuid,p_role public.app_role,p_sector public.sector,p_active boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 perform 1 from public.profiles order by id for update;
 if not exists(select 1 from public.profiles where id=p_user) then raise exception 'user_not_found';end if;
 if exists(select 1 from public.profiles where id=p_user and active and role='admin') and (p_role<>'admin' or not p_active)
 and not exists(select 1 from public.profiles where active and role='admin' and id<>p_user) then raise exception 'last_admin';end if;
 update public.profiles set role=p_role,sector=p_sector,active=p_active where id=p_user;
 delete from app_private.terminal_leases where user_id=p_user;
end $$;
-- Once issued, the payment code is stable even if merchant settings change.
create or replace function public.record_pix_artifact(p_attempt uuid,p_code text,p_expires timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.payment_attempts where id=p_attempt and method='pix' and status='pending') or length(p_code) not between 20 and 1000 then raise exception 'invalid_pix_artifact';end if;
 insert into app_private.payment_artifacts values(p_attempt,p_code,p_expires) on conflict(attempt_id) do nothing;
 if not exists(select 1 from app_private.payment_artifacts where attempt_id=p_attempt and copy_paste=p_code and expires_at is not distinct from p_expires) then raise exception 'pix_configuration_changed_reconcile';end if;
end $$;
commit;
