begin;
create table public.recipe_modifier_rules(
 product_id text not null references public.products(id),modifier text not null,ingredient_id uuid not null references public.ingredients(id),
 quantity_delta numeric(12,3) not null check(quantity_delta<>0),primary key(product_id,modifier,ingredient_id)
);
alter table public.recipe_modifier_rules enable row level security;
create policy modifier_rules_admin on public.recipe_modifier_rules for select to authenticated using(app_private.is_admin());
grant select on public.recipe_modifier_rules to authenticated;
create function app_private.audit_modifier_recipe() returns trigger language plpgsql security definer set search_path='' as $$
begin perform app_private.log('recipe.modifier_changed','product',case when tg_op='DELETE' then old.product_id else new.product_id end);if tg_op='DELETE' then return old;end if;return new;end $$;
create trigger modifier_recipe_audit after insert or update or delete on public.recipe_modifier_rules for each row execute function app_private.audit_modifier_recipe();
revoke execute on function public.save_recipe(text,jsonb,text) from authenticated;
create function public.save_recipe(p_product text,p_items jsonb,p_rules jsonb,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare rule jsonb; allowed text[];
begin
 if not app_private.is_admin() then raise exception 'access_denied' using errcode='42501';end if;
 perform app_private.reason(p_reason);
 if jsonb_typeof(p_rules)<>'array' or jsonb_array_length(p_rules)>100 then raise exception 'invalid_recipe_rules';end if;
 select allowed_modifiers into allowed from public.products where id=p_product for update;if not found then raise exception 'product_not_found';end if;
 delete from public.recipe_modifier_rules where product_id=p_product;
 perform public.save_recipe(p_product,p_items,p_reason);
 for rule in select * from jsonb_array_elements(p_rules) loop
  if not (rule->>'modifier')=any(allowed) or coalesce(rule->>'quantity_delta','') !~ '^-?[0-9]+(\.[0-9]{1,3})?$' then raise exception 'invalid_recipe_rule';end if;
  insert into public.recipe_modifier_rules values(p_product,rule->>'modifier',(rule->>'ingredient_id')::uuid,(rule->>'quantity_delta')::numeric);
 end loop;
end $$;
create function app_private.order_consumption(p_order uuid) returns table(ingredient_id uuid,quantity numeric) language sql stable security definer set search_path='' as $$
 with ingredient_options as(
  select i.id item_id,r.ingredient_id from public.order_items i join public.recipe_items r on r.product_id=i.product_id where i.order_id=p_order
  union
  select i.id,m.ingredient_id from public.order_items i join public.recipe_modifier_rules m on m.product_id=i.product_id and m.modifier=any(i.modifiers) where i.order_id=p_order
 ),consumption as(
 select opt.ingredient_id,i.quantity*greatest(0,
  coalesce((select r.quantity from public.recipe_items r where r.product_id=i.product_id and r.ingredient_id=opt.ingredient_id),0)+
  coalesce((select sum(m.quantity_delta) from public.recipe_modifier_rules m where m.product_id=i.product_id and m.ingredient_id=opt.ingredient_id and m.modifier=any(i.modifiers)),0)
 ) quantity from ingredient_options opt join public.order_items i on i.id=opt.item_id
 )select c.ingredient_id,sum(c.quantity) from consumption c group by c.ingredient_id having sum(c.quantity)>0
$$;
create or replace function app_private.release_order(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare ord public.orders; consumption record;
begin
 select * into ord from public.orders where id=p_order for update;
 if ord.status<>'pending_payment' then return;end if;
 if not exists(select 1 from public.payment_attempts where order_id=p_order and status='confirmed') then raise exception 'payment_required';end if;
 perform app_private.reason('Baixa por venda confirmada com ficha e modificadores');
 perform 1 from public.products where id in(select product_id from public.order_items where order_id=p_order) order by id for share;
 perform 1 from public.ingredients where id in(select x.ingredient_id from app_private.order_consumption(p_order) x) order by id for update;
 for consumption in select * from app_private.order_consumption(p_order) loop
  insert into public.stock_movements(order_id,ingredient_id,quantity) values(p_order,consumption.ingredient_id,-consumption.quantity);
  update public.ingredients set stock=stock-consumption.quantity where id=consumption.ingredient_id;
 end loop;
 insert into public.kitchen_tickets(order_id,order_number,customer,sector,items)
 select ord.id,ord.number,ord.customer,i.sector,jsonb_agg(jsonb_build_object('name',i.name,'quantity',i.quantity,'modifiers',i.modifiers,'notes',i.notes) order by i.id)
 from public.order_items i where i.order_id=p_order group by i.sector;
 update public.orders set status='queued',paid_at=now() where id=p_order;
 insert into public.integration_outbox(topic,order_id) values('order.paid',p_order) on conflict do nothing;
end $$;
revoke execute on function public.close_shift(uuid,int) from authenticated;
create function public.close_shift(p_shift uuid,p_counted_cents int,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin perform app_private.reason(p_reason);perform public.close_shift(p_shift,p_counted_cents);end $$;
create function app_private.audit_shift() returns trigger language plpgsql security definer set search_path='' as $$
declare expected bigint;
begin
 if tg_op='INSERT' then
  perform app_private.reason('Abertura de caixa com fundo de troco declarado');
  perform app_private.log('shift.opened','shift',new.id::text,new.opening_cents);
 elsif old.closed_at is null and new.closed_at is not null then
  expected:=(public.cash_summary(new.id)->>'expected_cents')::bigint;
  perform app_private.log('shift.closed','shift',new.id::text,new.closing_counted_cents-expected);
 end if;return new;
end $$;
create trigger shift_audit after insert or update on public.shifts for each row execute function app_private.audit_shift();
revoke all on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.role(),app_private.is_admin(),app_private.can_operate(),app_private.terminal_open() to authenticated;
grant execute on function public.save_recipe(text,jsonb,jsonb,text),public.close_shift(uuid,int,text) to authenticated;
commit;
