begin;
create function public.admin_metrics(p_from timestamptz,p_to timestamptz) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; peaks jsonb;margins jsonb;bottlenecks jsonb;low_stock jsonb;
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<=p_from or p_to-p_from>interval '366 days' then raise exception 'invalid_period';end if;
 select jsonb_build_object('paid_orders',count(*) filter(where paid_at is not null and status<>'cancelled'),'revenue_cents',coalesce(sum(total_cents) filter(where paid_at is not null and status<>'cancelled'),0),'discounts_cents',coalesce(sum(discount_cents) filter(where paid_at is not null and status<>'cancelled'),0),'cancelled',count(*) filter(where status='cancelled')) into result from public.orders where created_at>=p_from and created_at<p_to;
 select coalesce(jsonb_agg(row_to_json(x)),'[]') into peaks from(select extract(hour from paid_at at time zone 'America/Recife')::int as "hour",count(*) orders,sum(total_cents) revenue_cents from public.orders where paid_at>=p_from and paid_at<p_to and status<>'cancelled' group by 1 order by 1) x;
 select coalesce(jsonb_agg(row_to_json(x)),'[]') into margins from(
  with costs as(select r.product_id,sum(r.quantity*i.unit_cost_cents) cost_cents from public.recipe_items r join public.ingredients i on i.id=r.ingredient_id group by 1)
  select p.id,p.name,p.price_cents,c.cost_cents,p.price_cents-c.cost_cents margin_cents,coalesce(sold.quantity,0) quantity from public.products p left join costs c on c.product_id=p.id
  left join(select i.product_id,sum(i.quantity) quantity from public.order_items i join public.orders o on o.id=i.order_id where o.paid_at>=p_from and o.paid_at<p_to and o.status<>'cancelled' group by i.product_id) sold on sold.product_id=p.id order by margin_cents desc nulls last
 ) x;
 select coalesce(jsonb_agg(row_to_json(x)),'[]') into bottlenecks from(select sector,count(*) completed,round(avg(extract(epoch from started_at-created_at))) queue_seconds,round(avg(extract(epoch from ready_at-started_at))) prep_seconds from public.kitchen_tickets where ready_at>=p_from and ready_at<p_to and started_at is not null and status='ready' group by sector) x;
 select coalesce(jsonb_agg(row_to_json(x)),'[]') into low_stock from(select id,name,unit,stock,minimum_stock from public.ingredients where stock<=minimum_stock order by stock) x;
 perform app_private.reason('Consulta de indicadores agregados pelo administrador');perform app_private.log('report.viewed','report',p_from::text||'/'||p_to::text);
 return result||jsonb_build_object('cancelled_credit_cents',(select coalesce(sum(p.amount_cents),0) from public.payment_attempts p join public.orders o on o.id=p.order_id where o.status='cancelled' and p.status='confirmed'),'peaks',peaks,'margins',margins,'bottlenecks',bottlenecks,'low_stock',low_stock);
end $$;
grant execute on function public.admin_metrics(timestamptz,timestamptz) to authenticated;
commit;
