begin;
alter table public.payment_attempts add column confirmation_mode text not null default 'provider' check(confirmation_mode in ('provider','cash','manual_pix'));
update public.payment_attempts set confirmation_mode='cash' where method='cash';
create function app_private.payment_mode() returns trigger language plpgsql set search_path='' as $$
begin if new.method='cash' then new.confirmation_mode:='cash';end if;return new;end $$;
create trigger payment_mode before insert on public.payment_attempts for each row execute function app_private.payment_mode();
create or replace function public.record_pix_artifact(p_attempt uuid,p_code text,p_expires timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.payment_attempts where id=p_attempt and method='pix' and status='pending' for update;
 if not found or length(p_code) not between 20 and 1000 then raise exception 'invalid_pix_artifact';end if;
 insert into app_private.payment_artifacts values(p_attempt,p_code,p_expires) on conflict(attempt_id) do nothing;
 if not exists(select 1 from app_private.payment_artifacts where attempt_id=p_attempt and copy_paste=p_code and expires_at is not distinct from p_expires) then raise exception 'pix_configuration_changed_reconcile';end if;
 update public.payment_attempts set confirmation_mode=case when p_expires is null then 'manual_pix' else 'provider' end where id=p_attempt;
end $$;
create or replace function public.confirm_manual_pix(p_attempt uuid,p_bank_reference text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare payment public.payment_attempts;bankref text:=upper(regexp_replace(coalesce(p_bank_reference,''),'\s+','','g'));ord public.orders;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if bankref !~ '^[A-Z0-9._:-]{8,100}$' then raise exception 'bank_reference_required';end if;
 select * into payment from public.payment_attempts where id=p_attempt for update;
 if not found or payment.method<>'pix' or payment.confirmation_mode<>'manual_pix' or payment.status not in ('pending','failed','confirmed') then raise exception 'pix_confirmation_not_allowed';end if;
 if payment.status='confirmed' then if payment.provider_reference<>'manual-pix:'||bankref then raise exception 'reference_conflict';end if;return;end if;
 select * into ord from public.orders where id=payment.order_id for update;
 update public.payment_attempts set status='confirmed',provider_reference='manual-pix:'||bankref,confirmed_at=now() where id=p_attempt;
 perform app_private.log(case when ord.status='cancelled' then 'payment.pix_late_received' else 'payment.pix_manually_confirmed' end,'order',payment.order_id::text,payment.amount_cents);
 -- release_order deliberately does nothing for a cancelled order. A real late
 -- credit is recorded financially and can be refunded, never cooked silently.
 perform app_private.release_order(payment.order_id);
end $$;
create function public.void_pending_manual_pix(p_order uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare ord public.orders;attempt public.payment_attempts;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 select * into ord from public.orders where id=p_order for update;if not found then raise exception 'order_unavailable';end if;
 if ord.status='cancelled' then return;end if;
 if ord.status<>'pending_payment' then raise exception 'order_already_paid';end if;
 select * into attempt from public.payment_attempts where order_id=p_order and status='pending' for update;
 if not found or attempt.method<>'pix' or attempt.confirmation_mode<>'manual_pix' or attempt.provider_reference is not null then raise exception 'provider_reconciliation_required';end if;
 update public.payment_attempts set status='failed' where id=attempt.id;
 update public.orders set status='cancelled' where id=p_order;
 perform app_private.log('payment.manual_pix_closed_without_credit','order',p_order::text);
 insert into public.integration_outbox(topic,order_id) values('order.cancelled',p_order) on conflict do nothing;
end $$;
grant execute on function public.void_pending_manual_pix(uuid,text) to authenticated;
create or replace function public.confirm_provider_payment(p_attempt uuid,p_amount int,p_reference text,p_provider text,p_event text,p_payload_hash text) returns void language plpgsql security definer set search_path='' as $$
declare attempt public.payment_attempts; previous_hash text; previous_attempt uuid;
begin
 select * into attempt from public.payment_attempts where id=p_attempt for update;
 if not found or p_amount is null or coalesce(p_reference,'')='' or coalesce(p_provider,'')='' or coalesce(p_event,'')='' or coalesce(p_payload_hash,'')='' or (attempt.method='cash' or attempt.confirmation_mode<>'provider') or attempt.amount_cents<>p_amount or attempt.status not in ('pending','confirmed') then raise exception 'invalid_provider_payment'; end if;
 select payload_hash,attempt_id into previous_hash,previous_attempt from app_private.webhook_events where provider=p_provider and event_id=p_event;
 if found then
  if previous_hash<>p_payload_hash or previous_attempt<>p_attempt then raise exception 'event_conflict'; end if;
  return;
 end if;
 if attempt.provider_reference is not null and attempt.provider_reference<>p_reference then raise exception 'reference_conflict'; end if;
 insert into app_private.webhook_events values(p_provider,p_event,p_payload_hash,p_attempt,now());
 update public.payment_attempts set status='confirmed',provider_reference=p_reference,confirmed_at=coalesce(confirmed_at,now()) where id=p_attempt;
 perform app_private.release_order(attempt.order_id);
end $$;

commit;
