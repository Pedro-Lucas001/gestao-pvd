begin;
revoke execute on function public.record_whatsapp_reply(uuid) from authenticated;
create function public.record_whatsapp_reply(p_id uuid,p_actor uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles p join public.whatsapp_inbox i on i.id=p_id where p.id=p_actor and p.active and (p.role='admin' or (p.role='cashier' and i.assigned_to=p_actor and i.closed_at is null))) then raise exception 'access_denied' using errcode='42501';end if;
 insert into public.audit_log(actor_id,action,entity_type,entity_key,justification,actor_kind) values(p_actor,'whatsapp.reply','conversation',p_id::text,'Resposta enviada pela API oficial por operador autorizado','user');
end $$;
grant execute on function public.record_whatsapp_reply(uuid,uuid) to service_role;
commit;
