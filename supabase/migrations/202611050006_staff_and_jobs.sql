begin;
revoke execute on function public.manage_staff(uuid,public.app_role,public.sector,boolean) from authenticated;
create function public.manage_staff(p_user uuid,p_role public.app_role,p_sector public.sector,p_active boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 perform public.manage_staff(p_user,p_role,p_sector,p_active);
end $$;
create function public.retry_notification(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 update public.integration_outbox set attempts=0,next_attempt_at=now(),lease_until=null,last_error=null where id=p_id and delivered_at is null and (lease_until is null or lease_until<now());
 perform app_private.log('notification.retry','outbox',p_id::text);
end $$;
create function public.record_whatsapp_reply(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() and not (app_private.can_operate() and exists(select 1 from public.whatsapp_inbox where id=p_id and assigned_to=auth.uid() and closed_at is null)) then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason('Resposta de atendimento enviada pelo operador');perform app_private.log('whatsapp.reply','conversation',p_id::text);
end $$;
grant execute on function public.manage_staff(uuid,public.app_role,public.sector,boolean,text),public.retry_notification(uuid,text),public.record_whatsapp_reply(uuid) to authenticated;
commit;
