-- Run only as an administrator in a protected server-side report RPC, or with
-- the PostgreSQL administrator via SQL Editor. Do NOT grant this to cashiers.
-- Business timezone: America/Recife (Carpina). BRL in integer cents.

-- Peaks by local weekday and hour, based on paid orders.
select extract(isodow from paid_at at time zone 'America/Recife') weekday,
       extract(hour from paid_at at time zone 'America/Recife') as "hour",
       count(*) orders, sum(total_cents) revenue_cents
from public.orders where paid_at is not null and status<>'cancelled'
group by 1,2 order by 1,2;

-- Estimated contribution margin using CURRENT recipe cost (not historical
-- accounting). No recipe means UNKNOWN cost, never assume zero cost.
with recipe_cost as (
 select r.product_id,sum(r.quantity*i.unit_cost_cents) cost_cents
 from public.recipe_items r join public.ingredients i on i.id=r.ingredient_id
 group by r.product_id
)
select p.id,p.name,p.price_cents,r.cost_cents,
       p.price_cents-r.cost_cents margin_cents,
       round(100*(p.price_cents-r.cost_cents)/p.price_cents,2) margin_percent
from public.products p left join recipe_cost r on r.product_id=p.id
order by margin_percent desc nulls last;

-- Bottlenecks by sector. Include queue and prep separately.
select sector,count(*) completed,
 percentile_cont(.5) within group(order by extract(epoch from started_at-created_at)) median_queue_seconds,
 percentile_cont(.95) within group(order by extract(epoch from ready_at-started_at)) p95_prep_seconds
from public.kitchen_tickets where ready_at is not null and started_at is not null group by sector;

-- Real shortages/low stock must be visible to the manager immediately.
select id,name,unit,stock,minimum_stock from public.ingredients where stock<=minimum_stock order by stock;
