begin;
-- An append-only audit stream. Store amounts/reasons, never full customer rows,
-- PINs, tokens, passwords, card data or delivery addresses in audit payloads.
alter table public.audit_log add column amount_cents bigint not null default 0;
alter table public.audit_log add column justification text not null default 'Registro operacional anterior à auditoria avançada';
alter table public.audit_log add column quantity_delta numeric(14,3);
alter table public.audit_log add column entity_type text;
alter table public.audit_log add column entity_key text;
alter table public.audit_log add column actor_kind text not null default 'user' check(actor_kind in ('user','integration','system'));
create function app_private.immutable_log() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'immutable_audit_log' using errcode='42501'; end $$;
create trigger audit_no_changes before update or delete on public.audit_log for each row execute function app_private.immutable_log();
create trigger audit_no_truncate before truncate on public.audit_log for each statement execute function app_private.immutable_log();
revoke all on public.audit_log from anon,authenticated,service_role;
grant select on public.audit_log to authenticated;
create function app_private.reason(p_reason text) returns void language plpgsql set search_path='' as $$
begin
 if p_reason is null or length(trim(p_reason)) not between 5 and 500 then raise exception 'justification_required'; end if;
 perform set_config('app.audit_reason',trim(p_reason),true);
end $$;
create function app_private.log(p_action text,p_type text,p_key text,p_amount bigint default 0) returns void language plpgsql security definer set search_path='' as $$
declare reason text:=nullif(current_setting('app.audit_reason',true),''); actor uuid:=auth.uid();
begin
 if reason is null then raise exception 'justification_required'; end if;
 insert into public.audit_log(actor_id,action,entity_type,entity_key,amount_cents,justification,actor_kind)
 values(actor,p_action,p_type,p_key,p_amount,reason,case when actor is not null then 'user' when auth.jwt()->>'role'='service_role' then 'integration' else 'system' end);
end $$;
create function app_private.audit_insert_defaults() returns trigger language plpgsql set search_path='' as $$
begin
 if new.action='inventory.changed' then new.quantity_delta:=nullif(current_setting('app.audit_quantity',true),'')::numeric;end if;
 new.justification:=coalesce(nullif(current_setting('app.audit_reason',true),''),new.justification);
 if new.actor_id is null then new.actor_kind:=case when auth.jwt()->>'role'='service_role' then 'integration' else 'system' end; end if;
 return new;
end $$;
create trigger audit_insert_defaults before insert on public.audit_log for each row execute function app_private.audit_insert_defaults();

-- Registered device identity prevents bypassing a terminal lockout by submitting
-- random terminal IDs or switching staff accounts. Device tokens are never PINs.
create table public.terminals(id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 2 and 100),active boolean not null default true,created_at timestamptz not null default now());
create table app_private.terminal_secrets(terminal_id uuid primary key references public.terminals(id),token_hash text not null unique);
create table app_private.terminal_attempts(terminal_id uuid primary key references public.terminals(id),failures int not null default 0 check(failures between 0 and 4),locked_until timestamptz);
alter table public.terminals enable row level security;
create policy terminals_admin on public.terminals for select to authenticated using(app_private.is_admin());
grant select on public.terminals to authenticated;
delete from app_private.terminal_leases;
alter table app_private.terminal_leases add column terminal_id uuid not null references public.terminals(id);
create function public.register_terminal(p_name text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare device uuid; token text:=encode(extensions.gen_random_bytes(32),'hex');
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 perform app_private.reason(p_reason);
 insert into public.terminals(name) values(trim(p_name)) returning id into device;
 insert into app_private.terminal_secrets values(device,encode(extensions.digest(token,'sha256'),'hex'));
 insert into app_private.terminal_attempts(terminal_id) values(device);
 perform app_private.log('terminal.registered','terminal',device::text);
 return jsonb_build_object('id',device,'token',token);
end $$;
create function public.revoke_terminal(p_terminal uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 perform app_private.reason(p_reason);
 update public.terminals set active=false where id=p_terminal;
 delete from app_private.terminal_leases where terminal_id=p_terminal;
 perform app_private.log('terminal.revoked','terminal',p_terminal::text);
end $$;
create or replace function public.set_staff_pin(p_user uuid,p_pin text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 if p_pin is null or p_pin !~ '^[0-9]{4}$' or not exists(select 1 from public.profiles where id=p_user and active) then raise exception 'invalid_staff_pin'; end if;
 insert into app_private.pin_credentials(user_id,pin_hash) values(p_user,extensions.crypt(p_pin,extensions.gen_salt('bf',10)))
 on conflict(user_id) do update set pin_hash=excluded.pin_hash,failures=0,locked_until=null;
 delete from app_private.terminal_leases where user_id=p_user;
 perform app_private.reason('Definição ou troca de PIN de terminal');
 perform app_private.log('staff.pin_changed','profile',p_user::text);
end $$;
revoke execute on function public.unlock_terminal(text) from authenticated;
create function public.unlock_terminal(p_pin text,p_terminal_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare credential app_private.pin_credentials; device uuid; attempts app_private.terminal_attempts;
 sid text:=auth.jwt()->>'session_id'; expiry timestamptz:=now()+interval '10 minutes';
begin
 if app_private.role() is null or sid is null then raise exception 'access_denied' using errcode='42501'; end if;
 select s.terminal_id into device from app_private.terminal_secrets s join public.terminals d on d.id=s.terminal_id
 where s.token_hash=encode(extensions.digest(p_terminal_token,'sha256'),'hex') and d.active;
 if device is null then return jsonb_build_object('ok',false,'error','Terminal não cadastrado ou revogado. Solicite o cadastro ao administrador.'); end if;
 select * into attempts from app_private.terminal_attempts where terminal_id=device for update;
 if attempts.locked_until>now() then return jsonb_build_object('ok',false,'retry_at',attempts.locked_until,'error','Terminal bloqueado por 3 minutos após cinco erros consecutivos.'); end if;
 select * into credential from app_private.pin_credentials where user_id=auth.uid() for update;
 if not found then return jsonb_build_object('ok',false,'error','Seu PIN ainda não foi configurado pelo administrador.'); end if;
 if credential.locked_until>now() then return jsonb_build_object('ok',false,'retry_at',credential.locked_until,'error','Conta temporariamente bloqueada por 3 minutos.'); end if;
 if p_pin is null or p_pin !~ '^[0-9]{4}$' or extensions.crypt(p_pin,credential.pin_hash)<>credential.pin_hash then
  update app_private.terminal_attempts set failures=case when failures=4 then 0 else failures+1 end,
   locked_until=case when failures=4 then now()+interval '3 minutes' else null end where terminal_id=device returning * into attempts;
  update app_private.pin_credentials set failures=case when failures>=4 then 0 else failures+1 end,
   locked_until=case when failures>=4 then now()+interval '3 minutes' else null end where user_id=auth.uid();
  if attempts.locked_until is not null then
   perform app_private.reason('Cinco tentativas incorretas consecutivas no terminal');
   perform app_private.log('terminal.pin_lockout','terminal',device::text);
  end if;
  return jsonb_build_object('ok',false,'retry_at',attempts.locked_until,'error',case when attempts.locked_until is null then 'PIN incorreto.' else 'Terminal bloqueado por 3 minutos após cinco erros consecutivos.' end);
 end if;
 update app_private.terminal_attempts set failures=0,locked_until=null where terminal_id=device;
 update app_private.pin_credentials set failures=0,locked_until=null where user_id=auth.uid();
 insert into app_private.terminal_leases(user_id,session_id,expires_at,terminal_id) values(auth.uid(),sid,expiry,device)
 on conflict(user_id,session_id) do update set expires_at=excluded.expires_at,terminal_id=excluded.terminal_id;
 return jsonb_build_object('ok',true,'expires_at',expiry);
end $$;
create function app_private.terminal_open() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from app_private.terminal_leases l join public.terminals d on d.id=l.terminal_id where l.user_id=auth.uid() and l.session_id=auth.jwt()->>'session_id' and l.expires_at>now() and d.active)
$$;
create or replace function app_private.can_operate() returns boolean language sql stable security definer set search_path='' as $$
 select app_private.is_admin() or (app_private.role()='cashier' and app_private.terminal_open())
$$;
create function public.heartbeat_terminal() returns jsonb language plpgsql security definer set search_path='' as $$
declare expiry timestamptz;
begin
 if app_private.role() is null or not app_private.terminal_open() then return jsonb_build_object('ok',false); end if;
 update app_private.terminal_leases set expires_at=now()+interval '10 minutes' where user_id=auth.uid() and session_id=auth.jwt()->>'session_id' returning expires_at into expiry;
 return jsonb_build_object('ok',true,'expires_at',expiry);
end $$;
-- No name/phone/address in kitchen tickets. Use only the operational order alias.
update public.kitchen_tickets set customer='Pedido #'||order_number;
create function app_private.sanitize_ticket() returns trigger language plpgsql set search_path='' as $$
begin new.customer:='Pedido #'||new.order_number; return new; end $$;
create trigger sanitize_ticket before insert or update on public.kitchen_tickets for each row execute function app_private.sanitize_ticket();
drop policy ticket_read on public.kitchen_tickets;
create policy ticket_read on public.kitchen_tickets for select to authenticated using(app_private.is_admin() or (app_private.role()='kitchen' and app_private.terminal_open() and sector=(select p.sector from public.profiles p where p.id=auth.uid())));
-- Direct REST edits must not bypass validation, reasons and automatic audit.
revoke insert,update,delete on public.products,public.ingredients,public.recipe_items from authenticated;
-- Revoke broad service table writes. Integrations use narrowly scoped RPCs.
revoke insert,update,delete,truncate on all tables in schema public from service_role;
revoke all on public.audit_log from service_role;

revoke all on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.role(),app_private.is_admin(),app_private.can_operate(),app_private.terminal_open() to authenticated;
grant execute on function public.register_terminal(text,text),public.revoke_terminal(uuid,text),public.unlock_terminal(text,text),public.heartbeat_terminal() to authenticated;
create or replace function public.update_ticket(p_ticket uuid,p_status text) returns void language plpgsql security definer set search_path='' as $$
declare ticket public.kitchen_tickets;
begin
 if (not app_private.is_admin() and not app_private.terminal_open()) or app_private.role() not in ('admin','kitchen') or app_private.role() is null then raise exception 'access_denied' using errcode='42501'; end if;
 select * into ticket from public.kitchen_tickets where id=p_ticket for update;
 if not found or (not app_private.is_admin() and ticket.sector<>(select sector from public.profiles where id=auth.uid())) then raise exception 'access_denied' using errcode='42501'; end if;
 if ticket.status=p_status then return; end if;
 if not ((ticket.status='queued' and p_status='preparing') or (ticket.status='preparing' and p_status='ready')) then raise exception 'invalid_transition'; end if;
 perform 1 from public.orders where id=ticket.order_id for update;
 update public.kitchen_tickets set status=p_status,started_at=case when p_status='preparing' then now() else started_at end,ready_at=case when p_status='ready' then now() else ready_at end where id=p_ticket;
 update public.orders set status=case when not exists(select 1 from public.kitchen_tickets where order_id=ticket.order_id and status<>'ready') then 'ready'::public.order_state else 'preparing'::public.order_state end where id=ticket.order_id;
 insert into public.integration_outbox(topic,order_id) select 'order.ready',ticket.order_id where not exists(select 1 from public.kitchen_tickets where order_id=ticket.order_id and status<>'ready') on conflict do nothing;
end $$;

commit;
