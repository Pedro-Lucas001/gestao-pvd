begin;
create table public.kitchen_station_settings (
 sector public.sector primary key, reference_unit_seconds int not null check(reference_unit_seconds between 10 and 3600),
 parallel_capacity int not null check(parallel_capacity between 1 and 30), critical_items int not null check(critical_items between 1 and 999),
 updated_at timestamptz not null default now()
);
-- Referências iniciais editáveis; não representam tempos já medidos da lanchonete.
insert into public.kitchen_station_settings values('grill',180,3,15,now()),('fryer',240,2,15,now()),('bar',60,4,20,now());
create table public.kitchen_station_load (
 sector public.sector primary key references public.kitchen_station_settings(sector),
 queued_items int not null default 0, preparing_items int not null default 0,
 average_unit_seconds numeric not null, reference_unit_seconds int not null, sample_count int not null default 0,
 parallel_capacity int not null, critical_items int not null, updated_at timestamptz not null default now()
);
alter table public.kitchen_station_settings enable row level security;
alter table public.kitchen_station_load enable row level security;
create policy station_settings_admin on public.kitchen_station_settings for select to authenticated using(app_private.is_admin());
create policy station_load_read on public.kitchen_station_load for select to authenticated using(
 app_private.is_admin() or (app_private.role() in ('cashier','kitchen') and app_private.terminal_open()));
revoke all on public.kitchen_station_settings,public.kitchen_station_load from public,anon,authenticated,service_role;
grant select on public.kitchen_station_settings,public.kitchen_station_load to authenticated;
create index kitchen_active_sector_idx on public.kitchen_tickets(sector,status) where status in ('queued','preparing');
create index kitchen_recent_ready_idx on public.kitchen_tickets(sector,ready_at desc) where status='ready' and started_at is not null;

create function app_private.rebuild_kitchen_load() returns trigger language plpgsql security definer set search_path='' as $$
declare station public.kitchen_station_settings; queued int; preparing int; measured numeric; samples int;
begin
 -- Os três registros são bloqueados na mesma ordem antes do recálculo. O SELECT
 -- seguinte vê os commits precedentes, evitando perda de contagem entre caixas.
 perform 1 from public.kitchen_station_load order by sector for update;
 for station in select * from public.kitchen_station_settings order by sector loop
   select coalesce(sum(units) filter(where status='queued'),0),coalesce(sum(units) filter(where status='preparing'),0)
   into queued,preparing from (
     select t.status,(select sum((i->>'quantity')::int) from jsonb_array_elements(t.items) i) units
     from public.kitchen_tickets t where t.sector=station.sector and t.status in ('queued','preparing')
   ) active;
   -- Até 100 tickets concluídos nos últimos 30 dias, ponderados por quantidade.
   select round(sum(seconds)/nullif(sum(units),0),2),count(*) into measured,samples from (
     select extract(epoch from ready_at-started_at) seconds,
       (select sum((i->>'quantity')::int) from jsonb_array_elements(items) i) units
     from public.kitchen_tickets where sector=station.sector and status='ready'
       and ready_at>now()-interval '30 days' and ready_at>started_at
     order by ready_at desc limit 100
   ) recent where units>0;
   insert into public.kitchen_station_load(sector,queued_items,preparing_items,average_unit_seconds,reference_unit_seconds,sample_count,parallel_capacity,critical_items)
   values(station.sector,queued,preparing,coalesce(measured,station.reference_unit_seconds),station.reference_unit_seconds,samples,station.parallel_capacity,station.critical_items)
   on conflict(sector) do update set queued_items=excluded.queued_items,preparing_items=excluded.preparing_items,
     average_unit_seconds=excluded.average_unit_seconds,reference_unit_seconds=excluded.reference_unit_seconds,sample_count=excluded.sample_count,
     parallel_capacity=excluded.parallel_capacity,critical_items=excluded.critical_items,updated_at=clock_timestamp()
   where (kitchen_station_load.queued_items,kitchen_station_load.preparing_items,kitchen_station_load.average_unit_seconds,
     kitchen_station_load.reference_unit_seconds,kitchen_station_load.sample_count,kitchen_station_load.parallel_capacity,kitchen_station_load.critical_items)
    is distinct from (excluded.queued_items,excluded.preparing_items,excluded.average_unit_seconds,excluded.reference_unit_seconds,excluded.sample_count,excluded.parallel_capacity,excluded.critical_items);
 end loop;
 return null;
end $$;
-- Pré-cria as três linhas para que o lock tenha sempre um alvo, inclusive na primeira venda.
insert into public.kitchen_station_load(sector,average_unit_seconds,reference_unit_seconds,parallel_capacity,critical_items)
select sector,reference_unit_seconds,reference_unit_seconds,parallel_capacity,critical_items from public.kitchen_station_settings;
create trigger kitchen_load_changed after insert or update or delete on public.kitchen_tickets
for each statement execute function app_private.rebuild_kitchen_load();
create trigger kitchen_settings_changed after update on public.kitchen_station_settings
for each statement execute function app_private.rebuild_kitchen_load();
-- Dispara também o preenchimento inicial para tickets anteriores à migração.
update public.kitchen_station_settings set updated_at=now();

create function public.kitchen_load_snapshot() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() and (app_private.role() is null or app_private.role() not in ('cashier','kitchen') or not app_private.terminal_open()) then
   raise exception 'access_denied' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(s) order by sector) from public.kitchen_station_load s),'[]');
end $$;
create function public.set_kitchen_station(p_sector public.sector,p_seconds int,p_capacity int,p_critical int,p_reason text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 perform app_private.reason(p_reason);
 update public.kitchen_station_settings set reference_unit_seconds=p_seconds,parallel_capacity=p_capacity,
   critical_items=p_critical,updated_at=now() where sector=p_sector;
 perform app_private.log('kitchen.capacity_changed','sector',p_sector::text);
end $$;
revoke all on function app_private.rebuild_kitchen_load() from public,anon,authenticated,service_role;
revoke all on function public.kitchen_load_snapshot(),public.set_kitchen_station(public.sector,int,int,int,text) from public,anon,authenticated,service_role;
grant execute on function public.kitchen_load_snapshot(),public.set_kitchen_station(public.sector,int,int,int,text) to authenticated;
alter publication supabase_realtime add table public.kitchen_station_load;
commit;
