begin;
-- Custo da unidade no momento da baixa. Registros antigos ficam NULL, sem inventar histórico.
alter table public.stock_movements add column unit_cost_snapshot_cents int check(unit_cost_snapshot_cents>=0);
create function app_private.snapshot_ingredient_cost() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select unit_cost_cents into new.unit_cost_snapshot_cents from public.ingredients where id=new.ingredient_id;
 return new;
end $$;
create trigger stock_cost_snapshot before insert on public.stock_movements for each row execute function app_private.snapshot_ingredient_cost();
create table public.operating_expenses (
 id uuid primary key, description text not null check(length(trim(description)) between 2 and 150),
 amount_cents int not null check(amount_cents>0), expense_date date not null,
 justification text not null check(length(trim(justification)) between 5 and 500),
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
alter table public.operating_expenses enable row level security;
create policy operating_expenses_admin on public.operating_expenses for select to authenticated using(app_private.is_admin());
revoke all on public.operating_expenses from public,anon,authenticated,service_role;
grant select on public.operating_expenses to authenticated;
create index operating_expense_date_idx on public.operating_expenses(expense_date);
create trigger expense_immutable before update or delete or truncate on public.operating_expenses
for each statement execute function app_private.immutable_log();
create function public.record_operating_expense(p_key uuid,p_description text,p_amount int,p_date date,p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare previous public.operating_expenses;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 perform app_private.reason(p_reason);
 perform pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 select * into previous from public.operating_expenses where id=p_key;
 if found then
   if (previous.description,previous.amount_cents,previous.expense_date,previous.justification) is distinct from(trim(p_description),p_amount,p_date,trim(p_reason)) then raise exception 'idempotency_conflict'; end if;
   return previous.id;
 end if;
 insert into public.operating_expenses(id,description,amount_cents,expense_date,justification,created_by)
 values(p_key,trim(p_description),p_amount,p_date,trim(p_reason),auth.uid());
 perform app_private.log('expense.recorded','expense',p_key::text,p_amount);
 return p_key;
end $$;
create function public.admin_dre(p_from timestamptz,p_to timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sales bigint;discounts bigint;returns bigint;cost numeric;expenses bigint;legacy int;missing int;entries jsonb;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<=p_from or p_to-p_from>interval '366 days' then raise exception 'invalid_period'; end if;
 select coalesce(sum(total_cents),0),coalesce(sum(discount_cents),0) into sales,discounts
 from public.orders where paid_at>=p_from and paid_at<p_to;
 select coalesce(sum(p.amount_cents),0) into returns from public.payment_attempts p join public.orders o on o.id=p.order_id
 where o.paid_at>=p_from and o.paid_at<p_to and p.status='refunded';
 select coalesce(sum(-m.quantity*coalesce(m.unit_cost_snapshot_cents,i.unit_cost_cents)),0),count(*) filter(where m.unit_cost_snapshot_cents is null)
 into cost,legacy from public.stock_movements m join public.ingredients i on i.id=m.ingredient_id join public.orders o on o.id=m.order_id
 where o.paid_at>=p_from and o.paid_at<p_to;
 select count(distinct oi.product_id) into missing from public.order_items oi join public.orders o on o.id=oi.order_id
 where o.paid_at>=p_from and o.paid_at<p_to and not exists(select 1 from public.recipe_items r where r.product_id=oi.product_id);
 select coalesce(sum(amount_cents),0) into expenses from public.operating_expenses
 where expense_date>=(p_from at time zone 'America/Recife')::date and expense_date<(p_to at time zone 'America/Recife')::date;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.expense_date desc,e.created_at desc),'[]') into entries
 from public.operating_expenses e where expense_date>=(p_from at time zone 'America/Recife')::date and expense_date<(p_to at time zone 'America/Recife')::date;
 return jsonb_build_object('sales_cents',sales,'discounts_cents',discounts,'refunds_cents',returns,
   'net_revenue_cents',sales-returns,'cost_cents',round(cost),'expense_cents',expenses,
   'result_cents',case when missing>0 then null else sales-returns-round(cost)-expenses end,
   'legacy_cost_entries',legacy,'products_without_recipe',missing,'expenses',entries);
end $$;
revoke all on function app_private.snapshot_ingredient_cost() from public,anon,authenticated,service_role;
revoke all on function public.record_operating_expense(uuid,text,int,date,text),public.admin_dre(timestamptz,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.record_operating_expense(uuid,text,int,date,text),public.admin_dre(timestamptz,timestamptz) to authenticated;
commit;
