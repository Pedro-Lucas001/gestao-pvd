begin;

-- Internal tables are accessed through their existing privileged functions.
-- RLS adds a default deny layer if application-role grants change later.
alter table app_private.admin_cost_coverage enable row level security;
alter table app_private.integration_settings enable row level security;
alter table app_private.manual_bank_references enable row level security;
alter table app_private.message_replies enable row level security;
alter table app_private.online_ai_permissions enable row level security;
alter table app_private.online_allocations enable row level security;
alter table app_private.online_change_votes enable row level security;
alter table app_private.online_contacts enable row level security;
alter table app_private.online_handoffs enable row level security;
alter table app_private.online_payment_events enable row level security;
alter table app_private.online_rate_limits enable row level security;
alter table app_private.order_link_secrets enable row level security;
alter table app_private.order_tracking enable row level security;
alter table app_private.payment_artifacts enable row level security;
alter table app_private.pin_credentials enable row level security;
alter table app_private.terminal_attempts enable row level security;
alter table app_private.terminal_leases enable row level security;
alter table app_private.terminal_secrets enable row level security;
alter table app_private.webhook_events enable row level security;

commit;
