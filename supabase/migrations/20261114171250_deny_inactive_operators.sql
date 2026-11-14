begin;

create or replace function app_private.can_operate()
returns boolean
language sql stable security definer
set search_path=''
as $$
  select app_private.is_admin()
    or (coalesce(app_private.role()='cashier', false) and app_private.terminal_open())
$$;

commit;
