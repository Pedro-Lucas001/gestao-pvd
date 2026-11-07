begin;
create function app_private.online_payment(p_order uuid,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.online_orders;p public.online_payments;c app_private.online_contacts;
begin
 select * into o from public.online_orders where id=p_order for update;
 if not found or o.status<>'payment_pending' or o.payment_method not in ('pix','card') or o.total_cents<=o.paid_cents then raise exception 'payment_not_allowed';end if;
 select * into p from public.online_payments where id=p_key;
 if found and (p.order_id<>o.id or p.revision<>o.revision) then raise exception 'idempotency_conflict';end if;
 select * into p from public.online_payments where order_id=o.id and status='pending';
 if not found then insert into public.online_payments(id,order_id,revision,method,amount_cents) values(p_key,o.id,o.revision,o.payment_method,o.total_cents-o.paid_cents) returning * into p;end if;
 select * into c from app_private.online_contacts where order_id=o.id;
 return jsonb_build_object('id',p.id,'order_id',o.id,'number',o.number,'amount_cents',p.amount_cents,'method',p.method,'status',p.status,'creation_state',p.creation_state,'provider_reference',p.provider_reference,'checkout_url',p.checkout_url,'pix_code',p.pix_code,'expires_at',p.expires_at,'email',c.email);
end $$;
create or replace function public.online_prepare_payment(p_tracking text,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.online_orders;
begin o:=app_private.online_resolve(p_tracking);return app_private.online_payment(o.id,p_key);end $$;
create function public.online_claim_payment_creation(p_payment uuid) returns text language plpgsql security definer set search_path='' as $$
declare p public.online_payments;
begin
 select * into p from public.online_payments where id=p_payment and status='pending' for update;
 if not found then raise exception 'payment_not_allowed';end if;
 if p.creation_state='ready' then return 'ready';end if;
 if p.creation_state='creating' and p.creation_lease_until>now() then return 'busy';end if;
 update public.online_payments set creation_state='creating',creation_lease_until=now()+interval '1 minute' where id=p.id;
 return case when p.creation_state='new' then 'new' else 'recover' end;
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_claim_payment_creation' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
create function public.online_uncertain_payment(p_payment uuid) returns void language sql security definer set search_path='' as $$
 update public.online_payments set creation_state='uncertain',creation_lease_until=null where id=p_payment and creation_state='creating'
$$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_uncertain_payment' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;

-- A referência bancária não pode conciliar simultaneamente uma venda PDV e uma online.
create table app_private.manual_bank_references(reference text primary key,payment_identity text not null unique);
insert into app_private.manual_bank_references select provider_reference,'pos:'||id::text from public.payment_attempts where status='confirmed' and provider_reference like 'manual-pix:%';
create function app_private.unique_manual_bank_reference() returns trigger language plpgsql security definer set search_path='' as $$
declare ident text;existing text;
begin
 if new.status::text='confirmed' and new.provider_reference like 'manual-pix:%' then
  ident:=case when tg_table_name='online_payments' then 'online:' else 'pos:' end||new.id::text;
  insert into app_private.manual_bank_references values(new.provider_reference,ident) on conflict(reference) do nothing;
  select payment_identity into existing from app_private.manual_bank_references where reference=new.provider_reference;
  if existing<>ident then raise exception 'bank_reference_already_used' using errcode='23505';end if;
 end if;return new;
end $$;
create trigger online_bank_reference before insert or update on public.online_payments for each row execute function app_private.unique_manual_bank_reference();
create trigger pos_bank_reference before insert or update on public.payment_attempts for each row execute function app_private.unique_manual_bank_reference();
create function public.online_confirm_manual_pix(p_payment uuid,p_reference text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare p public.online_payments;ref text:=upper(regexp_replace(coalesce(p_reference,''),'\s+','','g'));
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;perform app_private.reason(p_reason);
 select * into p from public.online_payments where id=p_payment for update;
 if not found or p.method<>'pix' or p.provider<>'manual_pix' or p.pix_code is null or ref !~ '^[A-Z0-9._:-]{8,100}$' then raise exception 'manual_pix_not_allowed';end if;
 perform public.online_confirm_payment(p.id,p.amount_cents,'manual-pix:'||ref,'manual_pix','manual:'||p.id::text,encode(extensions.digest(ref,'sha256'),'hex'));
 perform app_private.log('online.manual_pix_confirmed','online_order',p.order_id::text,p.amount_cents);
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_confirm_manual_pix' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;

create or replace function public.cash_summary(p_shift uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare turn public.shifts;paid bigint;movements bigint;online_paid bigint;
begin
 if not coalesce(app_private.can_operate(),false) then raise exception 'access_denied' using errcode='42501';end if;
 select * into turn from public.shifts where id=p_shift and (cashier_id=auth.uid() or app_private.is_admin());if not found then raise exception 'shift_unavailable';end if;
 select coalesce(sum(p.amount_cents),0) into paid from public.payment_attempts p join public.orders o on o.id=p.order_id where o.shift_id=p_shift and p.method='cash' and p.status in ('confirmed','refunded');
 select coalesce(sum(p.amount_cents),0) into online_paid from public.online_payments p where p.shift_id=p_shift and p.method='cash' and p.status='confirmed';
 select coalesce(sum(case when kind='supply' then amount_cents else -amount_cents end),0) into movements from public.cash_movements where shift_id=p_shift;
 return jsonb_build_object('opening_cents',turn.opening_cents,'cash_sales_cents',paid+online_paid,'online_cash_sales_cents',online_paid,'movements_cents',movements,'expected_cents',turn.opening_cents+paid+online_paid+movements,'counted_cents',turn.closing_counted_cents,'closed_at',turn.closed_at);
end $$;
create function public.online_admin_metrics() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 return jsonb_build_object('received_cents',(select coalesce(sum(amount_cents),0) from public.online_payments where status='confirmed'),'refunded_cents',(select coalesce(sum(amount_cents),0) from public.online_refunds),'receivable_cents',(select coalesce(sum(greatest(0,total_cents-paid_cents)),0) from public.online_orders where status not in ('cancelled','awaiting_store')),'refund_due_cents',(select coalesce(sum(greatest(0,paid_cents-total_cents)),0) from public.online_orders),'stock_cost_cents',(select coalesce(round(sum(-quantity*unit_cost_cents)),0) from public.online_stock_movements));
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_admin_metrics' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;

create function public.online_claim_notifications() returns jsonb language plpgsql security definer set search_path='' as $$
declare job record;result jsonb:='[]';payment jsonb;
begin
 update public.online_notifications n set delivered_at=now(),last_error='superseded' from public.online_orders o where o.id=n.order_id and n.revision<o.revision and n.delivered_at is null;
 for job in
  with picked as(select n.id from public.online_notifications n join app_private.online_contacts c on c.order_id=n.order_id where n.delivered_at is null and n.attempts<8 and n.next_attempt_at<=now() and (n.lease_until is null or n.lease_until<now()) and c.whatsapp_consent order by n.next_attempt_at for update of n skip locked limit 2),claimed as(update public.online_notifications set lease_until=now()+interval '2 minutes',attempts=attempts+1 where id in(select id from picked) returning *)
  select n.*,o.number,o.status,o.payment_method,greatest(0,o.total_cents-o.paid_cents) due_cents,c.phone from claimed n join public.online_orders o on o.id=n.order_id join app_private.online_contacts c on c.order_id=n.order_id
 loop
  payment:=null;
  if job.topic='change.accepted' and job.due_cents>0 and job.status='payment_pending' and job.payment_method='pix' then payment:=app_private.online_payment(job.order_id,job.id);end if;
  result:=result||jsonb_build_array(jsonb_build_object('id',job.id,'topic',job.topic,'number',job.number,'due_cents',job.due_cents,'phone',job.phone,'payment',payment,'within_window',exists(select 1 from public.whatsapp_inbox i where i.sender=job.phone and i.received_at>now()-interval '23 hours')));
 end loop;return result;
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_claim_notifications' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
create function public.online_finish_notification(p_id uuid,p_success boolean,p_error text default null) returns void language sql security definer set search_path='' as $$
 update public.online_notifications set delivered_at=case when p_success then now() else null end,lease_until=null,next_attempt_at=now()+make_interval(secs=>least(3600,30*power(2,least(attempts,7))::int)),last_error=case when p_success then null else left(p_error,80) end where id=p_id and lease_until is not null
$$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_finish_notification' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
create function public.online_assistant_catalog() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('settings',public.online_shop_config(),'products',coalesce(jsonb_agg(jsonb_build_object('product_id',p.id,'name',p.name,'description',p.description,'category',p.category,'image_path',p.image_path,'price_cents',p.price_cents,'allowed_modifiers',p.allowed_modifiers) order by p.category,p.name),'[]')) from public.products p where p.active
$$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_assistant_catalog' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
create function public.online_automation_allowed(p_sender text,p_handoff boolean default false) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_handoff then
  insert into app_private.online_handoffs values(p_sender,now()+interval '24 hours') on conflict(sender) do update set paused_until=excluded.paused_until;
  return false;
 end if;
 return not exists(select 1 from app_private.online_handoffs where sender=p_sender and paused_until>now()) and not exists(select 1 from public.whatsapp_inbox where sender=p_sender and assigned_to is not null and closed_at is null);
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_automation_allowed' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
create function public.online_resume_automation(p_sender text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;perform app_private.reason(p_reason);
 delete from app_private.online_handoffs where sender=p_sender;
 perform app_private.log('online.automation_resumed','conversation',encode(extensions.digest(p_sender,'sha256'),'hex'));
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_resume_automation' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
revoke all on function app_private.online_payment(uuid,uuid),app_private.unique_manual_bank_reference() from public,anon,authenticated;
grant execute on function public.online_claim_payment_creation(uuid),public.online_uncertain_payment(uuid),public.online_claim_notifications(),public.online_finish_notification(uuid,boolean,text),public.online_assistant_catalog(),public.online_automation_allowed(text,boolean) to service_role;
grant execute on function public.online_confirm_manual_pix(uuid,text,text),public.online_admin_metrics(),public.online_resume_automation(text,text) to authenticated;
create function public.online_change_quote(p_tracking text,p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.online_orders;q jsonb;
begin
 o:=app_private.online_resolve(p_tracking);q:=app_private.online_items(p_items);
 return q||jsonb_build_object('delivery_fee_cents',o.delivery_fee_cents,'total_cents',(q->>'subtotal_cents')::int+o.delivery_fee_cents);
end $$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_change_quote' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
grant execute on function public.online_change_quote(text,jsonb) to service_role;
create function public.online_assistant_history(p_sender text) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('role','user','content',t.body) order by t.received_at),'[]') from(select body,received_at from public.whatsapp_inbox where sender=p_sender and received_at>now()-interval '23 hours' order by received_at desc limit 6) t
$$;
do $priv$ declare f regprocedure;begin for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='online_assistant_history' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f);end loop;end $priv$;
grant execute on function public.online_assistant_history(text) to service_role;
-- Abertura/fechamento e recebimento compartilham o lock do turno.
create or replace function public.close_shift(p_shift uuid,p_counted_cents int,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform app_private.reason(p_reason);
 perform 1 from public.shifts where id=p_shift for update;
 if exists(select 1 from public.online_orders where shift_id=p_shift and status not in ('completed','cancelled') and total_cents>paid_cents) then raise exception 'pending_orders_in_shift';end if;
 perform public.close_shift(p_shift,p_counted_cents);
end $$;
create table app_private.online_ai_permissions(sender text primary key,granted_at timestamptz not null,expires_at timestamptz not null);
create function public.online_ai_consent(p_sender text,p_message text) returns text language plpgsql security definer set search_path='' as $$
declare m text:=upper(trim(p_message));
begin
 if m in ('SEM IA','REVOGO IA','NAO AUTORIZO','NÃO AUTORIZO','HUMANO','ATENDENTE') then delete from app_private.online_ai_permissions where sender=p_sender;return 'revoked';end if;
 if m='AUTORIZO IA' then insert into app_private.online_ai_permissions values(p_sender,now(),now()+interval '30 days') on conflict(sender) do update set granted_at=excluded.granted_at,expires_at=excluded.expires_at;return 'granted';end if;
 if exists(select 1 from app_private.online_ai_permissions where sender=p_sender and expires_at>now()) then return 'granted';end if;return 'required';
end $$;
revoke all on function public.online_ai_consent(text,text) from public,anon,authenticated;
grant execute on function public.online_ai_consent(text,text) to service_role;
-- Uma chamada de IA pode demorar: um atendimento por lease, em ordem,
-- impede que a próxima mensagem do mesmo cliente corra em paralelo.
create or replace function public.claim_message_replies() returns jsonb language plpgsql security definer set search_path='' as $$
declare jobs jsonb;
begin
 perform pg_advisory_xact_lock(hashtextextended('online:ai-reply-claim',1));
 with pending as(
  select r.id from app_private.message_replies r join public.whatsapp_inbox i on i.id=r.inbox_id
  where r.state in ('pending','retry','running') and r.attempts<8 and r.next_attempt_at<=now() and (r.lease_until is null or r.lease_until<now())
  and not exists(select 1 from app_private.message_replies active join public.whatsapp_inbox other on other.id=active.inbox_id where active.id<>r.id and active.state='running' and active.lease_until>now() and other.sender=i.sender)
  order by i.received_at for update of r skip locked limit 1
 ),claimed as(update app_private.message_replies set state='running',lease_until=now()+interval '3 minutes',attempts=attempts+1 where id in(select id from pending) returning *)
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'sender',i.sender,'body',i.body,'received_at',i.received_at)),'[]') into jobs from claimed c join public.whatsapp_inbox i on i.id=c.inbox_id;
 return jobs;
end $$;
-- RPCs de serviço usadas pelo fluxo legado também precisam de revogação
-- explícita de PUBLIC; os grants de anon do checkout legado são preservados.
revoke all on function public.confirm_provider_payment(uuid,int,text,text,text,text),public.confirm_provider_refund(uuid,text,int),public.prepare_checkout_payment(text,uuid),public.record_pix_artifact(uuid,text,timestamptz),public.ingest_whatsapp(text,text,text,timestamptz),public.claim_notifications(int),public.finish_notification(uuid,boolean,text),public.claim_message_replies(),public.finish_message_reply(uuid,boolean),public.authenticate_staff_pin(text,text),public.bind_fastpass_session(uuid,text,text) from public,anon,authenticated;
commit;
