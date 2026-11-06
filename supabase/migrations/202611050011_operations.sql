begin;
create or replace function public.cash_movement(p_shift uuid,p_kind text,p_amount int,p_reason text,p_key uuid) returns void language plpgsql security definer set search_path='' as $$
declare previous public.cash_movements; balance bigint; turn public.shifts;
begin
 if not app_private.can_operate() or (p_kind='supply' and not app_private.is_admin()) then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if p_kind not in ('withdrawal','supply') or p_amount is null or p_amount<=0 then raise exception 'invalid_cash_movement';end if;
 select * into turn from public.shifts where id=p_shift and cashier_id=auth.uid() for update;if not found then raise exception 'shift_unavailable';end if;
 select * into previous from public.cash_movements where id=p_key;
 if found then if (previous.shift_id,previous.actor_id,previous.kind,previous.amount_cents,previous.justification) is distinct from (p_shift,auth.uid(),p_kind,p_amount,trim(p_reason)) then raise exception 'idempotency_conflict';end if;return;end if;
 if turn.closed_at is not null then raise exception 'shift_unavailable';end if;
 balance:=(public.cash_summary(p_shift)->>'expected_cents')::bigint;
 if p_kind='withdrawal' and p_amount>balance then raise exception 'insufficient_cash';end if;
 insert into public.cash_movements(id,shift_id,actor_id,kind,amount_cents,justification) values(p_key,p_shift,auth.uid(),p_kind,p_amount,trim(p_reason));
end $$;
drop policy inbox_need_to_know on public.whatsapp_inbox;
create policy inbox_need_to_know on public.whatsapp_inbox for select to authenticated using(app_private.is_admin() or (app_private.can_operate() and assigned_to=auth.uid() and closed_at is null and received_at>now()-interval '24 hours'));
create function public.close_conversation(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() and not (app_private.can_operate() and exists(select 1 from public.whatsapp_inbox where id=p_id and assigned_to=auth.uid() and closed_at is null and received_at>now()-interval '24 hours')) then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 update public.whatsapp_inbox set closed_at=now() where id=p_id and closed_at is null;
 perform app_private.log('whatsapp.closed','conversation',p_id::text);
end $$;
grant execute on function public.close_conversation(uuid,text) to authenticated;
commit;
