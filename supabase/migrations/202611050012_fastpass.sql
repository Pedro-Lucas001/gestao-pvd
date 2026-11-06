begin;
-- PIN identifica apenas funcionários; o Auth continua sendo a autoridade da sessão.
create table app_private.fastpass_challenges (
 token_hash text primary key, user_id uuid not null references public.profiles(id) on delete cascade,
 terminal_id uuid not null references public.terminals(id), credential_version text not null, expires_at timestamptz not null default now()+interval '60 seconds'
);
create table app_private.fastpass_sessions (
 user_id uuid not null references public.profiles(id) on delete cascade,
 session_id text not null unique, terminal_id uuid not null references public.terminals(id),
 created_at timestamptz not null default now(), primary key(user_id,session_id)
);
alter table app_private.fastpass_challenges enable row level security;
alter table app_private.fastpass_sessions enable row level security;
revoke all on app_private.fastpass_challenges,app_private.fastpass_sessions from public,anon,authenticated,service_role;

-- Uma sessão criada por PIN jamais adquire privilégios de admin, mesmo após promoção.
create or replace function app_private.role() returns public.app_role language sql stable security definer set search_path='' as $$
 select p.role from public.profiles p where p.id=auth.uid() and p.active
 and not (p.role='admin' and exists(select 1 from app_private.fastpass_sessions s
   where s.user_id=p.id and s.session_id=auth.jwt()->>'session_id'))
$$;
create function public.operator_context() returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(p)||jsonb_build_object('requires_password',p.role='admin' and exists(
   select 1 from app_private.fastpass_sessions s where s.user_id=p.id and s.session_id=auth.jwt()->>'session_id'))
 from public.profiles p where p.id=auth.uid()
$$;
revoke all on function public.operator_context() from public,anon,authenticated;
grant execute on function public.operator_context() to authenticated;

create or replace function public.set_staff_pin(p_user uuid,p_pin text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 if p_pin is null or p_pin !~ '^[0-9]{4}$' or not exists(select 1 from public.profiles where id=p_user and active) then raise exception 'invalid_staff_pin'; end if;
 perform pg_advisory_xact_lock(638194501);
 if exists(select 1 from public.profiles where id=p_user and role in ('cashier','kitchen')) and exists(
   select 1 from app_private.pin_credentials c join public.profiles p on p.id=c.user_id
   where c.user_id<>p_user and p.active and p.role in ('cashier','kitchen') and extensions.crypt(p_pin,c.pin_hash)=c.pin_hash
 ) then raise exception 'staff_pin_in_use'; end if;
 insert into app_private.pin_credentials(user_id,pin_hash) values(p_user,extensions.crypt(p_pin,extensions.gen_salt('bf',10)))
 on conflict(user_id) do update set pin_hash=excluded.pin_hash,failures=0,locked_until=null;
 delete from app_private.terminal_leases where user_id=p_user;
 delete from app_private.fastpass_challenges where user_id=p_user;
 perform app_private.reason('Definição ou troca de PIN individual do terminal');
 perform app_private.log('staff.pin_changed','profile',p_user::text);
end $$;

-- Chamável SOMENTE pelo Edge Function; nunca retorna hashes ou e-mail ao navegador.
create function public.authenticate_staff_pin(p_pin text,p_terminal_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare device uuid; attempts app_private.terminal_attempts; matches uuid[]; versions text[]; ticket text;
begin
 if p_terminal_token is null or p_terminal_token !~ '^[a-f0-9]{64}$' then
   return jsonb_build_object('ok',false,'error','TERMINAL_REQUIRED'); end if;
 select s.terminal_id into device from app_private.terminal_secrets s join public.terminals t on t.id=s.terminal_id
 where s.token_hash=encode(extensions.digest(p_terminal_token,'sha256'),'hex') and t.active;
 if not found then return jsonb_build_object('ok',false,'error','TERMINAL_REQUIRED'); end if;
 select * into attempts from app_private.terminal_attempts where terminal_id=device for update;
 if attempts.locked_until>now() then return jsonb_build_object('ok',false,'error','PIN_LOCKED','retry_at',attempts.locked_until); end if;
 if p_pin ~ '^[0-9]{4}$' then
   select array_agg(c.user_id),array_agg(encode(extensions.digest(c.pin_hash,'sha256'),'hex')) into matches,versions from app_private.pin_credentials c join public.profiles p on p.id=c.user_id
   where p.active and p.role in ('cashier','kitchen') and (c.locked_until is null or c.locked_until<=now())
   and extensions.crypt(p_pin,c.pin_hash)=c.pin_hash;
 end if;
 -- PINs legados duplicados falham fechados; o administrador deve definir PINs distintos.
 if coalesce(cardinality(matches),0)<>1 then
   update app_private.terminal_attempts set failures=case when failures=4 then 0 else failures+1 end,
    locked_until=case when failures=4 then now()+interval '3 minutes' else null end
    where terminal_id=device returning * into attempts;
   if attempts.locked_until is not null then
     perform app_private.reason('Cinco tentativas incorretas no acesso Fast-Pass');
     perform app_private.log('terminal.pin_lockout','terminal',device::text);
   end if;
   return jsonb_build_object('ok',false,'error',case when attempts.locked_until is null then 'INVALID_PIN' else 'PIN_LOCKED' end,'retry_at',attempts.locked_until);
 end if;
 update app_private.terminal_attempts set failures=0,locked_until=null where terminal_id=device;
 ticket:=encode(extensions.gen_random_bytes(32),'hex');
 delete from app_private.fastpass_challenges where expires_at<=now();
 insert into app_private.fastpass_challenges(token_hash,user_id,terminal_id,credential_version)
 values(encode(extensions.digest(ticket,'sha256'),'hex'),matches[1],device,versions[1]);
 return jsonb_build_object('ok',true,'user_id',matches[1],'challenge',ticket);
end $$;
create function public.bind_fastpass_session(p_user uuid,p_session_id text,p_challenge text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare challenge app_private.fastpass_challenges; expiry timestamptz:=now()+interval '10 minutes';
begin
 if p_session_id is null or p_session_id !~ '^[a-f0-9-]{36}$' or p_challenge is null or p_challenge !~ '^[a-f0-9]{64}$' then raise exception 'access_denied' using errcode='42501'; end if;
 select c.* into challenge from app_private.fastpass_challenges c join public.terminals t on t.id=c.terminal_id and t.active
   join public.profiles p on p.id=c.user_id and p.active and p.role in ('cashier','kitchen')
   join app_private.pin_credentials pin on pin.user_id=c.user_id and encode(extensions.digest(pin.pin_hash,'sha256'),'hex')=c.credential_version
 where c.token_hash=encode(extensions.digest(p_challenge,'sha256'),'hex') and c.user_id=p_user and c.expires_at>now() for update of c for share of pin;
 if not found then raise exception 'access_denied' using errcode='42501'; end if;
 delete from app_private.fastpass_challenges where token_hash=challenge.token_hash;
 insert into app_private.fastpass_sessions(user_id,session_id,terminal_id) values(p_user,p_session_id,challenge.terminal_id);
 insert into app_private.terminal_leases(user_id,session_id,expires_at,terminal_id) values(p_user,p_session_id,expiry,challenge.terminal_id)
 on conflict(user_id,session_id) do update set expires_at=excluded.expires_at,terminal_id=excluded.terminal_id;
 perform app_private.reason('Entrada individual Fast-Pass em terminal cadastrado');
 perform app_private.log('staff.fastpass_login','profile',p_user::text);
 return jsonb_build_object('ok',true,'expires_at',expiry);
end $$;
revoke all on function public.authenticate_staff_pin(text,text),public.bind_fastpass_session(uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.authenticate_staff_pin(text,text),public.bind_fastpass_session(uuid,text,text) to service_role;
commit;
