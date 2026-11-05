begin;
create table public.order_links(id uuid primary key default gen_random_uuid(),label text not null check(length(label) between 2 and 80),channel text not null check(channel in ('table','delivery')),active boolean not null default true,expires_at timestamptz not null,created_at timestamptz not null default now());
create table app_private.order_link_secrets(link_id uuid primary key references public.order_links(id),token_hash text not null unique,window_started timestamptz not null default now(),submissions int not null default 0);
create table app_private.order_tracking(order_id uuid primary key references public.orders(id),token_hash text not null unique,link_id uuid not null references public.order_links(id));
create table app_private.payment_artifacts(attempt_id uuid primary key references public.payment_attempts(id),copy_paste text not null,expires_at timestamptz);
create function public.create_order_link(p_label text,p_channel text,p_days int,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare link uuid; token text:=encode(extensions.gen_random_bytes(32),'hex');
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if p_days is null or p_days not between 1 and 90 then raise exception 'invalid_link_expiry';end if;
 insert into public.order_links(label,channel,expires_at) values(trim(p_label),p_channel,now()+make_interval(days=>p_days)) returning id into link;
 insert into app_private.order_link_secrets(link_id,token_hash) values(link,encode(extensions.digest(token,'sha256'),'hex'));
 perform app_private.log('checkout.link_created','order_link',link::text);
 return jsonb_build_object('id',link,'token',token);
end $$;
create function public.revoke_order_link(p_link uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);update public.order_links set active=false where id=p_link;
 perform app_private.log('checkout.link_revoked','order_link',p_link::text);
end $$;
create function app_private.order_link(p_token text) returns public.order_links language plpgsql security definer set search_path='' as $$
declare link public.order_links;
begin
 select l.* into link from public.order_links l join app_private.order_link_secrets s on s.link_id=l.id
 where s.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and l.active and l.expires_at>now();
 if not found then raise exception 'link_unavailable' using errcode='42501';end if;return link;
end $$;
create function public.checkout_menu(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare link public.order_links; catalog jsonb;
begin
 link:=app_private.order_link(p_token);
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category',p.category,'description',p.description,'price_cents',p.price_cents,'image_path',p.image_path,'allowed_modifiers',p.allowed_modifiers) order by p.category,p.price_cents),'[]') into catalog from public.products p where active;
 return jsonb_build_object('label',link.label,'channel',link.channel,'products',catalog);
end $$;
create function public.checkout_order(p_token text,p_key uuid,p_tracking text,p_contact jsonb,p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare link public.order_links; result public.orders; item jsonb; product public.products; qty int; mods text[];total bigint:=0;limiter app_private.order_link_secrets;
 request_hash text:=encode(extensions.digest(jsonb_build_object('contact',p_contact,'items',p_items)::text,'sha256'),'hex'); previous_hash text;
begin
 link:=app_private.order_link(p_token);
 if p_key is null or p_tracking is null or p_tracking !~ '^[a-f0-9]{64}$' then raise exception 'invalid_tracking_key';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 select o.* into result from public.orders o join app_private.order_tracking t on t.order_id=o.id where o.idempotency_key=p_key and t.link_id=link.id;
 if found then
  if result.request_body->>'request_hash'<>request_hash or not exists(select 1 from app_private.order_tracking where order_id=result.id and token_hash=encode(extensions.digest(p_tracking,'sha256'),'hex')) then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',result.id,'number',result.number,'total_cents',result.total_cents,'status',result.status);
 end if;
 select * into limiter from app_private.order_link_secrets where link_id=link.id for update;
 if limiter.window_started<now()-interval '1 minute' then update app_private.order_link_secrets set submissions=0,window_started=now() where link_id=link.id;limiter.submissions:=0;end if;
 if limiter.submissions>=10 then raise exception 'checkout_rate_limit';end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'invalid_items';end if;
 if length(trim(p_contact->>'name')) not between 2 and 100 or length(coalesce(p_contact->>'address',''))>500 or length(coalesce(p_contact->>'email',''))>254 then raise exception 'invalid_contact';end if;
 if link.channel='delivery' and (coalesce(p_contact->>'phone','') !~ '^\+?[0-9]{10,15}$' or length(trim(coalesce(p_contact->>'address','')))<10) then raise exception 'delivery_contact_required';end if;
 if coalesce((p_contact->>'whatsapp_consent')::boolean,false) and coalesce(p_contact->>'phone','') !~ '^\+?[0-9]{10,15}$' then raise exception 'phone_required_for_updates';end if;
 perform 1 from public.products where id in(select x->>'product_id' from jsonb_array_elements(p_items) x) order by id for share;
 for item in select * from jsonb_array_elements(p_items) loop
  select * into product from public.products where id=item->>'product_id' and active;if not found then raise exception 'product_unavailable';end if;
  if coalesce(item->>'quantity','') !~ '^[0-9]+$' then raise exception 'invalid_quantity';end if;qty:=(item->>'quantity')::int;if qty not between 1 and 100 then raise exception 'invalid_quantity';end if;
  mods:=array(select jsonb_array_elements_text(coalesce(item->'modifiers','[]')));
  if not mods<@product.allowed_modifiers or (select count(*) from unnest(mods) x where x like 'Ponto:%')>1 then raise exception 'invalid_modifier';end if;
  if length(coalesce(item->>'notes',''))>500 then raise exception 'notes_too_long';end if;
  total:=total+product.price_cents::bigint*qty;
 end loop;
 if total>1000000 then raise exception 'order_too_large';end if;
 insert into public.orders(source,idempotency_key,request_body,customer,channel,total_cents)
 values('self_service',p_key,jsonb_build_object('request_hash',request_hash),case when link.channel='table' then link.label else 'Delivery' end,link.channel,total) returning * into result;
 for item in select * from jsonb_array_elements(p_items) loop
  select * into product from public.products where id=item->>'product_id';
  insert into public.order_items(order_id,product_id,name,quantity,unit_price_cents,sector,modifiers,notes)
  values(result.id,product.id,product.name,(item->>'quantity')::int,product.price_cents,product.sector,array(select jsonb_array_elements_text(coalesce(item->'modifiers','[]'))),coalesce(item->>'notes',''));
 end loop;
 insert into app_private.order_tracking values(result.id,encode(extensions.digest(p_tracking,'sha256'),'hex'),link.id);
 insert into public.customer_contacts(order_id,name,phone,address,email,whatsapp_consent)
 values(result.id,trim(p_contact->>'name'),coalesce(p_contact->>'phone',''),coalesce(p_contact->>'address',''),coalesce(p_contact->>'email',''),coalesce((p_contact->>'whatsapp_consent')::boolean,false));
 update app_private.order_link_secrets set submissions=submissions+1 where link_id=link.id;
 return jsonb_build_object('id',result.id,'number',result.number,'total_cents',result.total_cents,'status',result.status);
end $$;
create function public.checkout_status(p_tracking text) returns jsonb language plpgsql security definer set search_path='' as $$
declare ord public.orders; attempt public.payment_attempts; artifact app_private.payment_artifacts;
begin
 select o.* into ord from public.orders o join app_private.order_tracking t on t.order_id=o.id where t.token_hash=encode(extensions.digest(p_tracking,'sha256'),'hex');
 if not found then raise exception 'order_unavailable' using errcode='42501';end if;
 select * into attempt from public.payment_attempts where order_id=ord.id order by created_at desc limit 1;
 select * into artifact from app_private.payment_artifacts where attempt_id=attempt.id;
 return jsonb_build_object('id',ord.id,'number',ord.number,'total_cents',ord.total_cents,'status',ord.status,'fulfillment_state',ord.fulfillment_state,'pix',case when artifact.attempt_id is null then null else jsonb_build_object('copyPaste',artifact.copy_paste,'expiresAt',artifact.expires_at) end);
end $$;
create function public.prepare_checkout_payment(p_tracking text,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare ord public.orders; attempt public.payment_attempts;
begin
 select o.* into ord from public.orders o join app_private.order_tracking t on t.order_id=o.id where t.token_hash=encode(extensions.digest(p_tracking,'sha256'),'hex') for update of o;
 if not found or ord.status<>'pending_payment' then raise exception 'payment_not_allowed';end if;
 select * into attempt from public.payment_attempts where order_id=ord.id and status='pending';
 if not found then
  insert into public.payment_attempts(id,order_id,method,amount_cents) values(p_key,ord.id,'pix',ord.total_cents) returning * into attempt;
 end if;
 if attempt.method<>'pix' then raise exception 'payment_reconciliation_required';end if;
 return jsonb_build_object('id',attempt.id,'amount_cents',attempt.amount_cents);
end $$;
create function public.record_pix_artifact(p_attempt uuid,p_code text,p_expires timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.payment_attempts where id=p_attempt and method='pix' and status='pending') or length(p_code) not between 20 and 1000 then raise exception 'invalid_pix_artifact';end if;
 insert into app_private.payment_artifacts values(p_attempt,p_code,p_expires) on conflict(attempt_id) do nothing;
end $$;
create function public.confirm_manual_pix(p_attempt uuid,p_bank_reference text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare payment public.payment_attempts;bankref text:=upper(regexp_replace(coalesce(p_bank_reference,''),'\s+','','g'));
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if bankref !~ '^[A-Z0-9._:-]{8,100}$' then raise exception 'bank_reference_required';end if;
 select * into payment from public.payment_attempts where id=p_attempt for update;
 if not found or payment.method<>'pix' or payment.status not in ('pending','confirmed') then raise exception 'pix_confirmation_not_allowed';end if;
 if payment.status='confirmed' then if payment.provider_reference<>'manual-pix:'||bankref then raise exception 'reference_conflict';end if;return;end if;
 update public.payment_attempts set status='confirmed',provider_reference='manual-pix:'||bankref,confirmed_at=now() where id=p_attempt;
 perform app_private.log('payment.pix_manually_confirmed','order',payment.order_id::text,payment.amount_cents);
 perform app_private.release_order(payment.order_id);
end $$;
create function public.confirm_manual_pix_refund(p_refund uuid,p_bank_reference text) returns void language plpgsql security definer set search_path='' as $$
declare bankref text:=upper(regexp_replace(coalesce(p_bank_reference,''),'\s+','','g'));
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 if bankref !~ '^[A-Z0-9._:-]{8,100}$' or not exists(select 1 from public.refunds r join public.payment_attempts p on p.id=r.payment_id where r.id=p_refund and p.method='pix' and p.provider_reference like 'manual-pix:%') then raise exception 'manual_refund_not_allowed';end if;
 perform app_private.finish_refund(p_refund,'manual-pix-refund:'||bankref);
end $$;

-- Server-side Meta ingestion: private message data is not in Realtime or KDS.
create function public.ingest_whatsapp(p_id text,p_sender text,p_text text,p_received timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare ident uuid;
begin
 if length(p_id) not between 5 and 200 or p_sender !~ '^[0-9]{10,15}$' or length(p_text)>2000 then raise exception 'invalid_message';end if;
 insert into public.whatsapp_inbox(provider_message_id,sender,body,received_at) values(p_id,p_sender,p_text,p_received)
 on conflict(provider_message_id) do nothing returning id into ident;
 if ident is not null then insert into app_private.message_replies(inbox_id) values(ident);end if;
 return ident;
end $$;
create function public.assign_whatsapp(p_id uuid,p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 if not exists(select 1 from public.profiles where id=p_user and active and role in ('admin','cashier')) then raise exception 'invalid_operator';end if;
 update public.whatsapp_inbox set assigned_to=p_user where id=p_id;
 perform app_private.reason('Atribuição de conversa ao operador de atendimento');perform app_private.log('whatsapp.assigned','conversation',p_id::text);
end $$;
-- Claim jobs transactionally; expired leases may retry after a crashed worker.
-- Delivery is at-least-once: Meta has no general send idempotency key. A timeout
-- may duplicate a notification, never a charge or a kitchen ticket.
alter table public.integration_outbox add column lease_until timestamptz;
alter table public.integration_outbox add column last_error text;
create function public.claim_notifications(p_limit int default 10) returns jsonb language plpgsql security definer set search_path='' as $$
declare jobs jsonb;
begin
 with claimed as (
  select o.id from public.integration_outbox o join public.customer_contacts c on c.order_id=o.order_id
  where o.delivered_at is null and o.attempts<8 and o.next_attempt_at<=now() and (o.lease_until is null or o.lease_until<now()) and c.whatsapp_consent and c.erased_at is null and c.phone<>''
  order by o.next_attempt_at for update of o skip locked limit least(greatest(p_limit,1),20)
 ),updated as (
  update public.integration_outbox o set lease_until=now()+interval '2 minutes',attempts=attempts+1 where id in(select id from claimed) returning o.*
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'topic',u.topic,'order_number',ord.number,'phone',c.phone,'attempts',u.attempts,'within_window',exists(select 1 from public.whatsapp_inbox i where i.sender=regexp_replace(c.phone,'[^0-9]','','g') and i.received_at>now()-interval '23 hours'))),'[]') into jobs
 from updated u join public.orders ord on ord.id=u.order_id join public.customer_contacts c on c.order_id=u.order_id;
 return jobs;
end $$;
create function public.finish_notification(p_id uuid,p_success boolean,p_error text default null) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.integration_outbox set delivered_at=case when p_success then now() else null end,lease_until=null,
 next_attempt_at=now()+make_interval(secs=>least(3600,30*power(2,least(attempts,7))::int)),last_error=case when p_success then null else left(p_error,80) end where id=p_id and lease_until is not null;
end $$;
create function public.claim_message_replies() returns jsonb language plpgsql security definer set search_path='' as $$
declare jobs jsonb;
begin
 with pending as(select id from app_private.message_replies where state in ('pending','retry','running') and attempts<8 and next_attempt_at<=now() and (lease_until is null or lease_until<now()) order by next_attempt_at for update skip locked limit 10),claimed as(
 update app_private.message_replies set state='running',lease_until=now()+interval '2 minutes',attempts=attempts+1 where id in(select id from pending) returning * )
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'sender',i.sender,'body',i.body,'received_at',i.received_at)),'[]') into jobs from claimed c join public.whatsapp_inbox i on i.id=c.inbox_id;
 return jobs;
end $$;
create function public.finish_message_reply(p_id uuid,p_success boolean) returns void language plpgsql security definer set search_path='' as $$
begin update app_private.message_replies set state=case when p_success then 'delivered' else 'retry' end,lease_until=null,next_attempt_at=now()+interval '5 minutes' where id=p_id and state='running';end $$;

alter table public.order_links enable row level security;
create policy links_admin on public.order_links for select to authenticated using(app_private.is_admin());
grant select on public.order_links to authenticated;
revoke all on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.role(),app_private.is_admin(),app_private.can_operate(),app_private.terminal_open() to authenticated;
grant execute on function public.create_order_link(text,text,int,text),public.revoke_order_link(uuid,text),public.confirm_manual_pix(uuid,text,text),public.confirm_manual_pix_refund(uuid,text),public.assign_whatsapp(uuid,uuid) to authenticated;
grant execute on function public.checkout_menu(text),public.checkout_order(text,uuid,text,jsonb,jsonb),public.checkout_status(text) to anon,authenticated;
grant execute on function public.prepare_checkout_payment(text,uuid),public.record_pix_artifact(uuid,text,timestamptz),public.ingest_whatsapp(text,text,text,timestamptz),public.claim_notifications(int),public.finish_notification(uuid,boolean,text),public.claim_message_replies(),public.finish_message_reply(uuid,boolean) to service_role;
commit;
