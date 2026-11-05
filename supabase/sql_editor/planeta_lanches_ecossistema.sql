-- PARTES 5 E 6 — aplique DEPOIS de planeta_lanches_completo.sql.
-- Contrato em português. Não combinar com a sequência de migrations em inglês.
begin;
do $$ begin
  if to_regtype('public.pedido_status') is null or to_regnamespace('planeta_private') is null then
    raise exception 'Execute primeiro planeta_lanches_completo.sql.';
  end if;
  if to_regclass('public.customers') is not null then raise exception 'Ecossistema já instalado; não reaplicar.'; end if;
end $$;

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  anonimizado_em timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Nenhuma tabela pública de clientes contém telefone, nome civil, endereço ou texto da conversa.
create table planeta_private.customer_data (
  customer_id uuid primary key references public.customers(id) on delete cascade,
  nome text not null default 'Cliente' check (length(nome) between 1 and 120),
  telefone text unique not null check (telefone ~ '^[0-9]{10,15}$'),
  endereco jsonb not null default '{}' check (jsonb_typeof(endereco)='object' and octet_length(endereco::text)<=4096),
  last_inbound_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table planeta_private.customer_consent (
  customer_id uuid primary key references public.customers(id) on delete cascade,
  marketing_opt_in boolean not null default false,
  fonte text not null default 'nao_fornecido',
  consentido_em timestamptz,
  revogado_em timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.integration_sources (
  id text primary key check (id ~ '^[a-z][a-z0-9_-]{1,39}$'),
  nome text not null check (length(nome) between 1 and 100),
  ativo boolean not null default false,
  scopes text[] not null default array['orders']::text[] check(scopes <@ array['orders','fulfillment','ads']::text[]),
  -- Conta interna de serviço, criada no Auth e configurada pelo administrador.
  user_id uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into public.integration_sources(id,nome) values ('whatsapp','WhatsApp oficial');
create table public.integration_product_map (
  source_id text not null references public.integration_sources(id) on delete cascade,
  external_sku text not null check (length(external_sku) between 1 and 100),
  product_id uuid not null references public.products(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(source_id,external_sku)
);
create table public.integration_events (
  id uuid primary key default gen_random_uuid(),
  source_id text not null references public.integration_sources(id),
  external_event_id text not null check (length(external_event_id) between 1 and 200),
  external_order_id text not null check (length(external_order_id) between 1 and 200),
  order_id uuid not null,
  payload_hash bytea not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_id,external_event_id),
  unique(source_id,external_order_id)
);
alter table public.orders
  add column customer_id uuid references public.customers(id) on delete restrict,
  add column assigned_to uuid references public.profiles(id) on delete restrict,
  add column external_source text references public.integration_sources(id),
  add column logistics_source text references public.integration_sources(id),
  add column pagamento_status text not null default 'aguardando'
    check (pagamento_status in ('aguardando','confirmado','estornado')),
  add column pagamento_referencia text,
  add column pagamento_confirmado_em timestamptz;
create unique index orders_payment_ref_idx on public.orders(lower(btrim(pagamento_referencia)))
  where pagamento_referencia is not null;
create index orders_customer_idx on public.orders(customer_id,created_at desc);
create index orders_assigned_idx on public.orders(assigned_to);

create table public.loyalty_settings (
  id boolean primary key default true check (id),
  pontos_por_real numeric(8,4) not null default 1 check (pontos_por_real between 0 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into public.loyalty_settings(id) values(true);
-- Ledger, não saldo editável. 1 ponto/R$ 1 por padrão, sem promessa de valor em dinheiro.
create table public.loyalty_points (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id),
  order_id uuid not null references public.orders(id) on delete restrict,
  tipo text not null check (tipo in ('credito','estorno')),
  pontos bigint not null check ((tipo='credito' and pontos>=0) or (tipo='estorno' and pontos<=0)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(order_id,tipo)
);
create index loyalty_customer_idx on public.loyalty_points(customer_id);
create table public.marketing_campaigns (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (length(nome) between 1 and 150),
  -- Template SEM parâmetros, já aprovado na Meta como MARKETING.
  template_name text not null check (length(template_name) between 1 and 512 and template_name ~ '^[a-z0-9_]+$'),
  template_language text not null default 'pt_BR' check (template_language ~ '^[a-z]{2}(_[A-Z]{2})?$'),
  status text not null default 'rascunho' check (status in ('rascunho','enviando','concluida','cancelada')),
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.marketing_deliveries (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.marketing_campaigns(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  status text not null default 'pendente' check (status in ('pendente','enviando','enviado','cancelado','falhou')),
  tentativas integer not null default 0,
  lease_token uuid,
  lease_until timestamptz,
  enviado_em timestamptz,
  provider_message_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(campaign_id,customer_id)
);
create index marketing_queue_idx on public.marketing_deliveries(status,lease_until);
create table public.lgpd_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  tipo text not null check (tipo in ('acesso','anonimizacao')),
  status text not null default 'pendente' check (status in ('pendente','concluido')),
  concluido_em timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index lgpd_pending_idx on public.lgpd_requests(customer_id,status);
create table planeta_private.privacy_tokens (
  token_hash bytea primary key,
  customer_id uuid not null references public.customers(id) on delete cascade,
  expires_at timestamptz not null default now()+interval '15 minutes',
  used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table planeta_private.privacy_receipts (
  token_hash bytea primary key,
  resultado jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table planeta_private.rate_windows (
  chave text primary key,
  inicio timestamptz not null default clock_timestamp(),
  quantidade integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table planeta_private.whatsapp_receipts (
  id text primary key,
  received_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table planeta_private.whatsapp_jobs (
  id text primary key check (length(id) between 1 and 200),
  customer_id uuid not null references public.customers(id),
  texto text not null check (length(texto)<=4000),
  received_at timestamptz not null,
  status text not null default 'pendente' check (status in ('pendente','processando','concluido','falhou')),
  tentativas integer not null default 0,
  lease_token uuid,
  lease_until timestamptz,
  outbound_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index whatsapp_jobs_queue_idx on planeta_private.whatsapp_jobs(status,lease_until,received_at);
create table planeta_private.chat_messages (
  id bigint generated always as identity primary key,
  customer_id uuid not null references public.customers(id),
  job_id text not null references planeta_private.whatsapp_jobs(id) on delete cascade,
  role text not null check(role in ('user','assistant')),
  content text not null check(length(content)<=6000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(job_id,role)
);
create index chat_customer_idx on planeta_private.chat_messages(customer_id,created_at desc);
create table planeta_private.sales_drafts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  job_id text unique not null references planeta_private.whatsapp_jobs(id) on delete cascade,
  itens jsonb not null,
  tipo text not null check(tipo in ('balcao','delivery')),
  metodo_pagamento text not null check(metodo_pagamento in ('pix','dinheiro','cartao')),
  total numeric(12,2) not null,
  order_id uuid,
  expires_at timestamptz not null default now()+interval '30 minutes',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index draft_customer_idx on planeta_private.sales_drafts(customer_id,created_at desc);

create function planeta_private.limitar(p_chave text,p_max integer,p_segundos integer) returns void
language plpgsql security definer set search_path='' as $$
declare janela planeta_private.rate_windows; momento timestamptz:=clock_timestamp();
begin
  insert into planeta_private.rate_windows(chave) values(p_chave) on conflict do nothing;
  select * into janela from planeta_private.rate_windows where chave=p_chave for update;
  if janela.inicio+make_interval(secs=>p_segundos)<=momento then
    update planeta_private.rate_windows set inicio=momento,quantidade=1 where chave=p_chave;
  elsif janela.quantidade>=p_max then raise exception 'Limite temporário de requisições.' using errcode='P0001';
  else update planeta_private.rate_windows set quantidade=quantidade+1 where chave=p_chave;
  end if;
end $$;

create or replace function planeta_private.pedido_do_caixa(p_id uuid,p_pendente boolean) returns boolean
language sql stable security definer set search_path='' as $$
  select planeta_private.role_atual()='caixa' and exists(
    select 1 from public.orders where id=p_id and (user_id=auth.uid() or assigned_to=auth.uid())
      and (not p_pendente or status='pendente'))
$$;
drop policy orders_caixa_ler on public.orders;
create policy orders_caixa_ler on public.orders for select to authenticated
using (planeta_private.pedido_do_caixa(id,false));
drop policy orders_cozinha_ler on public.orders;
create policy orders_cozinha_ler on public.orders for select to authenticated
using ((select planeta_private.role_atual())='cozinha' and pagamento_status='confirmado');
drop policy orders_cozinha_status on public.orders;
create policy orders_cozinha_status on public.orders for update to authenticated
using ((select planeta_private.role_atual())='cozinha' and pagamento_status='confirmado')
with check ((select planeta_private.role_atual())='cozinha' and pagamento_status='confirmado');
drop policy items_cozinha_ler on public.order_items;
create function planeta_private.pedido_kds(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select planeta_private.role_atual()='cozinha' and exists(
    select 1 from public.orders where id=p_id and pagamento_status='confirmado')
$$;
create policy items_cozinha_ler on public.order_items for select to authenticated
using (planeta_private.pedido_kds(order_id));
create or replace view public.orders_gestao with (security_barrier=true) as
select o.* from public.orders o where planeta_private.role_atual()='admin' or planeta_private.pedido_do_caixa(o.id,false);

-- SELECT de PII só por pedido autorizado e com limitação de consultas; nenhum SELECT da base.
create function public.contato_do_pedido(p_order_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pedido public.orders; contato jsonb;
begin
  select * into pedido from public.orders where id=p_order_id;
  if not found or (planeta_private.role_atual() is distinct from 'admin'
    and not planeta_private.pedido_do_caixa(p_order_id,false)) then
    raise exception 'Acesso negado.' using errcode='42501';
  end if;
  if pedido.status in ('entregue','cancelado') then raise exception 'Contato indisponível após encerramento.'; end if;
  perform planeta_private.limitar('contact:'||auth.uid(),30,60);
  select jsonb_build_object('nome',nome,'telefone',telefone,'endereco',endereco) into contato
    from planeta_private.customer_data where customer_id=pedido.customer_id;
  insert into public.audit_logs(user_id,acao,tabela_afetada,dados_novos)
  values(auth.uid(),'CONSULTA_CONTATO','customers',jsonb_build_object('customer_id',pedido.customer_id,'order_id',pedido.id));
  return contato;
end $$;
create function public.assumir_pedido(p_order_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  if planeta_private.role_atual() not in ('admin','caixa') or planeta_private.role_atual() is null then
    raise exception 'Acesso negado.' using errcode='42501'; end if;
  update public.orders set assigned_to=auth.uid() where id=p_order_id and external_source is not null
    and assigned_to is null and status='pendente';
  if not found then raise exception 'Pedido indisponível para atribuição.'; end if;
end $$;
create function planeta_private.payment_gate() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    if auth.uid() is not null and (new.customer_id is not null or new.external_source is not null) then
      raise exception 'Vínculo de cliente/canal exige fluxo de integração verificado.' using errcode='42501';
    end if;
    new.pagamento_status:='aguardando'; new.pagamento_referencia:=null; new.pagamento_confirmado_em:=null;
  elsif new.status in ('preparando','pronto','entregue') and new.pagamento_status<>'confirmado' then
    -- Permite registrar um estorno financeiro depois da entrega sem reabrir a cozinha.
    if not (new.status=old.status and new.pagamento_status='estornado') then
      raise exception 'Pagamento confirmado é obrigatório antes da produção.';
    end if;
  end if;
  return new;
end $$;
create trigger orders_payment_gate before insert or update on public.orders
for each row execute function planeta_private.payment_gate();
-- Fecha a edição financeira depois da conciliação e impede alterações retroativas de cliente.
create function planeta_private.proteger_venda() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' then
    if old.pagamento_status<>'aguardando' and old.status<>'cancelado' then
      raise exception 'Venda conciliada deve ser encerrada/cancelada, não excluída.';
    end if;
    return old;
  end if;
  if new.customer_id is distinct from old.customer_id or new.external_source is distinct from old.external_source then
    raise exception 'Origem e cliente da venda são imutáveis.';
  end if;
  if old.pagamento_status<>'aguardando' and
    (new.metodo_pagamento<>old.metodo_pagamento or new.tipo<>old.tipo or new.total<>old.total) then
    raise exception 'Venda conciliada não pode alterar valores, método ou tipo.';
  end if;
  if (old.pagamento_status='confirmado' and new.pagamento_status='aguardando')
    or (old.pagamento_status='estornado' and new.pagamento_status<>'estornado') then
    raise exception 'Conciliação não pode ser reaberta.';
  end if;
  return new;
end $$;
create trigger orders_proteger before update or delete on public.orders
for each row execute function planeta_private.proteger_venda();
create function planeta_private.proteger_item_pago() returns trigger
language plpgsql security definer set search_path='' as $$
declare pedido public.orders; chave uuid;
begin
  chave:=case when tg_op='DELETE' then old.order_id else new.order_id end;
  select * into pedido from public.orders where id=chave for update;
  if found and pedido.pagamento_status<>'aguardando' and not(tg_op='DELETE' and pedido.status='cancelado') then
    raise exception 'Itens de venda conciliada não podem ser alterados.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
create trigger order_items_pagamento before insert or update or delete on public.order_items
for each row execute function planeta_private.proteger_item_pago();

create function public.confirmar_pagamento(p_order_id uuid,p_referencia text) returns void
language plpgsql security definer set search_path='' as $$
declare pedido public.orders; papel public.equipe_role:=planeta_private.role_atual();
begin
  select * into pedido from public.orders where id=p_order_id for update;
  if not found or papel is null or papel='cozinha' or
     (papel='caixa' and (pedido.metodo_pagamento<>'dinheiro' or not planeta_private.pedido_do_caixa(p_order_id,false))) then
    raise exception 'Acesso negado; Pix/cartão exigem conciliação pelo admin.' using errcode='42501';
  end if;
  if pedido.pagamento_status='estornado' then raise exception 'Pagamento estornado não pode ser reaberto.'; end if;
  if pedido.status='cancelado' then raise exception 'Pedido cancelado: registre a conciliação/estorno fora deste fluxo.'; end if;
  if p_referencia is null or length(btrim(p_referencia)) not between 5 and 160 then
    raise exception 'Informe referência verificável do recebimento.'; end if;
  if pedido.pagamento_status='confirmado' then
    if lower(btrim(p_referencia))=lower(pedido.pagamento_referencia) then return; end if;
    raise exception 'Pagamento já conciliado com outra referência.';
  end if;
  update public.orders set pagamento_status='confirmado',pagamento_referencia=btrim(p_referencia),
    pagamento_confirmado_em=clock_timestamp() where id=p_order_id;
end $$;
-- Não há endpoint público de confirmação. Meta/IA/marketplace não marcam Pix como pago.

create function planeta_private.pontuar() returns trigger
language plpgsql security definer set search_path='' as $$
declare credito public.loyalty_points;
begin
  if new.status='entregue' and new.pagamento_status='confirmado' and new.customer_id is not null then
    insert into public.loyalty_points(customer_id,order_id,tipo,pontos)
    select new.customer_id,new.id,'credito',floor(new.total*pontos_por_real)::bigint
    from public.loyalty_settings where id on conflict(order_id,tipo) do nothing;
  elsif new.pagamento_status='estornado' or new.status='cancelado' then
    select * into credito from public.loyalty_points where order_id=new.id and tipo='credito';
    if found then insert into public.loyalty_points(customer_id,order_id,tipo,pontos)
      values(credito.customer_id,new.id,'estorno',-credito.pontos) on conflict(order_id,tipo) do nothing; end if;
  end if;
  return null;
end $$;
create trigger orders_loyalty after update of status,pagamento_status on public.orders
for each row execute function planeta_private.pontuar();
create trigger loyalty_imutavel before update or delete or truncate on public.loyalty_points
for each statement execute function planeta_private.bloquear_auditoria();

-- Visão sem dados pessoais: só admin; nunca disponibilizada ao modelo de IA.
create view public.clientes_inativos_15_dias with (security_barrier=true) as
select c.id as customer_id,max(o.created_at) as ultima_compra
from public.customers c
join public.orders o on o.customer_id=c.id and o.status='entregue' and o.pagamento_status='confirmado'
join planeta_private.customer_consent s on s.customer_id=c.id and s.marketing_opt_in
where planeta_private.role_atual()='admin' and c.anonimizado_em is null
  and not exists(select 1 from public.lgpd_requests r where r.customer_id=c.id and r.tipo='anonimizacao')
group by c.id having max(o.created_at)<now()-interval '15 days';

create function public.iniciar_campanha(p_id uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare quantidade integer; campanha public.marketing_campaigns;
begin
  if planeta_private.role_atual() is distinct from 'admin' then raise exception 'Acesso negado.' using errcode='42501'; end if;
  select * into campanha from public.marketing_campaigns where id=p_id for update;
  if not found or campanha.status<>'rascunho' then raise exception 'Campanha indisponível.'; end if;
  insert into public.marketing_deliveries(campaign_id,customer_id)
  select p_id,customer_id from public.clientes_inativos_15_dias c
  where not exists(select 1 from public.marketing_deliveries d where d.customer_id=c.customer_id
    and d.enviado_em>now()-interval '7 days') on conflict do nothing;
  get diagnostics quantidade=row_count;
  update public.marketing_campaigns set status=case when quantidade=0 then 'concluida' else 'enviando' end where id=p_id;
  return quantidade;
end $$;

-- Uma única criação de venda, compartilhada pelo WhatsApp e pelos adaptadores de marketplace.
create function planeta_private.criar_venda(p_source text,p_customer uuid,p_itens jsonb,p_tipo text,p_metodo text)
returns uuid language plpgsql security definer set search_path='' as $$
declare autor uuid; pedido uuid:=gen_random_uuid(); item jsonb; mods jsonb; chave text;
begin
  select s.user_id into autor from public.integration_sources s join public.profiles p on p.id=s.user_id
    where s.id=p_source and s.ativo and 'orders'=any(s.scopes) and p.ativo and p.role in ('admin','caixa');
  if autor is null then raise exception 'Canal não configurado.'; end if;
  if p_customer is not null then
    perform 1 from public.customers where id=p_customer and anonimizado_em is null for update;
    if not found or exists(select 1 from public.lgpd_requests where customer_id=p_customer and tipo='anonimizacao') then
      raise exception 'Cliente com exclusão solicitada; encaminhe ao atendimento.'; end if;
  end if;
  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) not between 1 and 50 then
    raise exception 'Itens inválidos.'; end if;
  if p_tipo='delivery' and not exists(select 1 from planeta_private.customer_data where customer_id=p_customer and endereco<>'{}') then
    raise exception 'Endereço de entrega obrigatório.'; end if;
  insert into public.orders(id,user_id,customer_id,external_source,metodo_pagamento,tipo)
  values(pedido,autor,p_customer,p_source,p_metodo,p_tipo);
  for item in select value from jsonb_array_elements(p_itens) loop
    mods:=coalesce(item->'modificadores','{}');
    if jsonb_typeof(mods)<>'object' then raise exception 'Modificadores inválidos.'; end if;
    for chave in select jsonb_object_keys(mods) loop
      if chave='ponto' then
        if mods->>chave not in ('bem passado','ao ponto','mal passado') or jsonb_typeof(mods->chave)<>'string' then
          raise exception 'Ponto inválido.'; end if;
      elsif chave not in ('cebola','tomate','alface','milho','batata_palha','queijo','bacon')
        or jsonb_typeof(mods->chave)<>'boolean' then raise exception 'Modificador não permitido.';
      end if;
    end loop;
    insert into public.order_items(order_id,product_id,quantidade,modificadores)
    values(pedido,(item->>'product_id')::uuid,(item->>'quantidade')::integer,mods);
  end loop;
  return pedido;
end $$;
create function public.eco_ingest_order(p_source text,p_event_id text,p_external_order_id text,p_payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare existente public.integration_events; itens jsonb:='[]'; item jsonb; produto uuid; pedido uuid;
begin
  if jsonb_typeof(p_payload) is distinct from 'object' or (p_payload - array['itens','tipo','metodo_pagamento'])<>'{}'::jsonb then
    raise exception 'Payload não permitido: envie apenas itens, tipo e método.'; end if;
  perform planeta_private.limitar('source:'||p_source,120,60);
  -- Serializa os dois identificadores: eventos diferentes para o mesmo pedido não duplicam venda.
  perform pg_advisory_xact_lock(hashtextextended(p_source||':'||p_external_order_id,0));
  select * into existente from public.integration_events
    where source_id=p_source and (external_event_id=p_event_id or external_order_id=p_external_order_id);
  if found then
    if existente.external_order_id<>p_external_order_id or existente.payload_hash<>extensions.digest(p_payload::text,'sha256') then
      raise exception 'Conflito de idempotência.'; end if;
    return existente.order_id;
  end if;
  if jsonb_typeof(p_payload->'itens') is distinct from 'array' or jsonb_array_length(p_payload->'itens') not between 1 and 50 then
    raise exception 'Itens inválidos.'; end if;
  for item in select value from jsonb_array_elements(p_payload->'itens') loop
    if jsonb_typeof(item) is distinct from 'object' or (item-array['sku','quantidade','modificadores'])<>'{}'::jsonb then
      raise exception 'Campos não permitidos no item externo.'; end if;
    select product_id into produto from public.integration_product_map
      where source_id=p_source and external_sku=item->>'sku';
    if not found then raise exception 'SKU externo sem mapeamento.'; end if;
    itens:=itens||jsonb_build_array(jsonb_build_object('product_id',produto,'quantidade',item->'quantidade',
      'modificadores',coalesce(item->'modificadores','{}')));
  end loop;
  -- Delivery exige coleta segura de endereço; payload genérico não injeta PII/pagamentos.
  if p_payload->>'tipo' is distinct from 'balcao' then raise exception 'Adaptador genérico aceita retirada no balcão; delivery exige adaptador dedicado.'; end if;
  pedido:=planeta_private.criar_venda(p_source,null,itens,'balcao',p_payload->>'metodo_pagamento');
  insert into public.integration_events(source_id,external_event_id,external_order_id,order_id,payload_hash)
  values(p_source,p_event_id,p_external_order_id,pedido,extensions.digest(p_payload::text,'sha256'));
  return pedido;
end $$;

-- Webhook recebe texto somente após validação da assinatura Meta no Edge.
create function public.eco_ingest_whatsapp(p_id text,p_phone text,p_text text,p_received timestamptz,p_nome text)
returns void language plpgsql security definer set search_path='' as $$
declare cliente uuid; comando text:=lower(btrim(p_text));
begin
  if p_phone is null or p_phone !~ '^[0-9]{10,15}$' or p_text is null or length(p_text)>4000
    or p_received is null or p_received>now()+interval '5 minutes' then raise exception 'Mensagem inválida.'; end if;
  if p_received<now()-interval '7 days' then return; end if;
  if exists(select 1 from planeta_private.whatsapp_receipts where id=p_id) then return; end if;
  perform pg_advisory_xact_lock(hashtextextended('wa:'||p_phone,0));
  insert into planeta_private.whatsapp_receipts(id,received_at) values(p_id,p_received) on conflict do nothing;
  if not found then return; end if;
  select customer_id into cliente from planeta_private.customer_data where telefone=p_phone;
  if not found then
    insert into public.customers default values returning id into cliente;
    insert into planeta_private.customer_data(customer_id,nome,telefone,last_inbound_at)
    values(cliente,coalesce(nullif(left(btrim(p_nome),120),''),'Cliente'),p_phone,p_received);
    insert into planeta_private.customer_consent(customer_id) values(cliente);
  else
    update planeta_private.customer_data set last_inbound_at=greatest(last_inbound_at,p_received) where customer_id=cliente;
  end if;
  perform planeta_private.limitar('wa:'||cliente,30,60);
  insert into planeta_private.whatsapp_jobs(id,customer_id,texto,received_at) values(p_id,cliente,p_text,p_received);
  insert into planeta_private.chat_messages(customer_id,job_id,role,content) values(cliente,p_id,'user',p_text);
  -- Opt-out aplicado no recebimento, antes de qualquer worker ou IA.
  if comando in ('sair','parar','cancelar marketing','quero receber promoções') then
    update planeta_private.customer_consent set marketing_opt_in=(comando='quero receber promoções'),
      fonte='whatsapp_comando_explicito',
      consentido_em=case when comando='quero receber promoções' then clock_timestamp() else consentido_em end,
      revogado_em=case when comando<>'quero receber promoções' then clock_timestamp() else null end
    where customer_id=cliente;
    if comando<>'quero receber promoções' then
      update public.marketing_deliveries set status='cancelado',lease_token=null,lease_until=null
      where customer_id=cliente and status in ('pendente','enviando');
    end if;
    insert into public.audit_logs(acao,tabela_afetada,dados_novos)
    values('CONSENTIMENTO_MARKETING','customers',jsonb_build_object('customer_id',cliente,'opt_in',comando='quero receber promoções'));
  end if;
end $$;
create function public.eco_claim_whatsapp() returns jsonb
language plpgsql security definer set search_path='' as $$
declare trabalho planeta_private.whatsapp_jobs; contato planeta_private.customer_data;
begin
  -- Não processa duas mensagens do mesmo cliente simultaneamente e respeita a janela de 24h.
  select j.* into trabalho from planeta_private.whatsapp_jobs j
  join planeta_private.customer_data d on d.customer_id=j.customer_id
  where ((j.status='pendente' and (j.lease_until is null or j.lease_until<now())) or (j.status='processando' and j.lease_until<now()))
    and j.tentativas<8 and d.last_inbound_at>now()-interval '23 hours 55 minutes'
    and not exists(select 1 from planeta_private.whatsapp_jobs anterior where anterior.customer_id=j.customer_id
      and anterior.received_at<j.received_at and anterior.status in ('pendente','processando') and anterior.tentativas<8)
  order by j.received_at,j.id for update of j skip locked limit 1;
  if not found then return null; end if;
  -- Lock transacional impede claims concorrentes para mensagens com timestamp igual.
  if not pg_try_advisory_xact_lock(hashtextextended('chat:'||trabalho.customer_id,0)) then return null; end if;
  if exists(select 1 from planeta_private.whatsapp_jobs where customer_id=trabalho.customer_id
    and status='processando' and lease_until>now() and id<>trabalho.id) then return null; end if;
  update planeta_private.whatsapp_jobs set status='processando',tentativas=tentativas+1,
    lease_token=gen_random_uuid(),lease_until=now()+interval '2 minutes' where id=trabalho.id returning * into trabalho;
  select * into contato from planeta_private.customer_data where customer_id=trabalho.customer_id;
  return jsonb_build_object('id',trabalho.id,'lease_token',trabalho.lease_token,'texto',trabalho.texto,'telefone',contato.telefone);
end $$;
create function planeta_private.job_valido(p_id text,p_lease uuid) returns planeta_private.whatsapp_jobs
language plpgsql security definer set search_path='' as $$
declare trabalho planeta_private.whatsapp_jobs;
begin
  select * into trabalho from planeta_private.whatsapp_jobs where id=p_id and lease_token=p_lease
    and status='processando' and lease_until>now() for update;
  if not found then raise exception 'Lease inválido.' using errcode='42501'; end if;
  return trabalho;
end $$;
create function public.eco_ai_context(p_id text,p_lease uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare trabalho planeta_private.whatsapp_jobs; menu jsonb; conversa jsonb;
begin
  trabalho:=planeta_private.job_valido(p_id,p_lease);
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'nome',p.nome,'descricao',p.descricao,
    'preco',p.preco,'categoria',c.nome) order by c.nome,p.nome),'[]') into menu
  from public.products p join public.categories c on c.id=p.category_id where p.ativo;
  select coalesce(jsonb_agg(jsonb_build_object('role',role,'content',content) order by created_at),'[]') into conversa
  from (select role,regexp_replace(content,'[0-9a-f]{64}','[segredo removido]','gi') as content,created_at from planeta_private.chat_messages
    where customer_id=trabalho.customer_id order by created_at desc limit 10) h;
  -- O modelo recebe texto/menu, mas não uma listagem de clientes, telefone, endereço salvo ou segredos.
  return jsonb_build_object('menu',menu,'conversa',conversa,'humano_ativo',exists(
    select 1 from public.ai_handoffs where customer_id=trabalho.customer_id and status<>'concluido') or exists(
    select 1 from public.lgpd_requests where customer_id=trabalho.customer_id and tipo='anonimizacao'));
end $$;
create function public.eco_ai_propose(p_id text,p_lease uuid,p_itens jsonb,p_tipo text,p_metodo text,p_endereco jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare trabalho planeta_private.whatsapp_jobs; item jsonb; produto public.products;
  itens jsonb:='[]'; valor numeric(12,2):=0; unidades integer; rascunho planeta_private.sales_drafts;
begin
  trabalho:=planeta_private.job_valido(p_id,p_lease);
  select * into rascunho from planeta_private.sales_drafts where job_id=p_id;
  if found then return jsonb_build_object('id',rascunho.id,'itens',rascunho.itens,'total',rascunho.total); end if;
  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) not between 1 and 50 then raise exception 'Itens inválidos.'; end if;
  for item in select value from jsonb_array_elements(p_itens) loop
    unidades:=(item->>'quantidade')::integer;
    if unidades is null or unidades not between 1 and 999 then raise exception 'Quantidade inválida.'; end if;
    select * into produto from public.products where id=(item->>'product_id')::uuid and ativo;
    if not found then raise exception 'Produto indisponível.'; end if;
    valor:=valor+produto.preco*unidades;
    itens:=itens||jsonb_build_array(jsonb_build_object('product_id',produto.id,'nome',produto.nome,
      'quantidade',unidades,'preco_unitario',produto.preco,'modificadores',coalesce(item->'modificadores','{}')));
  end loop;
  if p_tipo='delivery' then
    if jsonb_typeof(p_endereco) is distinct from 'object' or length(coalesce(p_endereco->>'logradouro','')) not between 3 and 200
      or length(coalesce(p_endereco->>'numero','')) not between 1 and 30
      or length(coalesce(p_endereco->>'bairro','')) not between 2 and 100 then raise exception 'Endereço incompleto.'; end if;
    update planeta_private.customer_data set endereco=jsonb_build_object('logradouro',left(p_endereco->>'logradouro',200),
      'numero',left(p_endereco->>'numero',30),'bairro',left(p_endereco->>'bairro',100),
      'complemento',left(coalesce(p_endereco->>'complemento',''),200)) where customer_id=trabalho.customer_id;
  end if;
  insert into planeta_private.sales_drafts(customer_id,job_id,itens,tipo,metodo_pagamento,total)
  values(trabalho.customer_id,p_id,itens,p_tipo,p_metodo,valor) returning * into rascunho;
  return jsonb_build_object('id',rascunho.id,'itens',itens,'total',valor);
end $$;
create function public.eco_ai_confirm(p_id text,p_lease uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare trabalho planeta_private.whatsapp_jobs; rascunho planeta_private.sales_drafts; pedido uuid; item jsonb; atual numeric;
begin
  trabalho:=planeta_private.job_valido(p_id,p_lease);
  if lower(btrim(trabalho.texto))<>'confirmar' then raise exception 'Confirmação explícita obrigatória.'; end if;
  select * into rascunho from planeta_private.sales_drafts where customer_id=trabalho.customer_id
    order by created_at desc limit 1 for update;
  if not found or rascunho.expires_at<=now() then raise exception 'Resumo expirado; solicite um novo.'; end if;
  if rascunho.order_id is not null then return jsonb_build_object('order_id',rascunho.order_id,'total',rascunho.total); end if;
  for item in select value from jsonb_array_elements(rascunho.itens) loop
    select preco into atual from public.products where id=(item->>'product_id')::uuid and ativo for share;
    if not found or atual<>(item->>'preco_unitario')::numeric then raise exception 'Cardápio mudou; solicite novo resumo.'; end if;
  end loop;
  pedido:=planeta_private.criar_venda('whatsapp',trabalho.customer_id,rascunho.itens,rascunho.tipo,rascunho.metodo_pagamento);
  update planeta_private.sales_drafts set order_id=pedido where id=rascunho.id;
  return jsonb_build_object('order_id',pedido,'total',rascunho.total);
end $$;
create function public.eco_finish_whatsapp(p_id text,p_lease uuid,p_reply text,p_outbound_id text,p_success boolean)
returns void language plpgsql security definer set search_path='' as $$
declare trabalho planeta_private.whatsapp_jobs;
begin
  trabalho:=planeta_private.job_valido(p_id,p_lease);
  if p_success then
    insert into planeta_private.chat_messages(customer_id,job_id,role,content)
    values(trabalho.customer_id,p_id,'assistant',left(regexp_replace(p_reply,'[0-9a-f]{64}','[segredo removido]','gi'),6000)) on conflict(job_id,role) do nothing;
  end if;
  update planeta_private.whatsapp_jobs set status=case when p_success then 'concluido'
    when tentativas>=8 then 'falhou' else 'pendente' end,
    outbound_id=p_outbound_id,lease_until=case when p_success then null else now()+interval '2 minutes' end,lease_token=null where id=p_id;
end $$;

create function planeta_private.anonimizar(p_customer uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.customers where id=p_customer for update;
  -- Dados mínimos ainda necessários para cumprir um pedido: conclusão pendente e automática.
  if exists(select 1 from public.orders where customer_id=p_customer and status not in ('entregue','cancelado')) then return false; end if;
  delete from public.integration_outbox e using public.orders o where e.order_id=o.id and o.customer_id=p_customer and e.status='pendente';
  delete from planeta_private.customer_data where customer_id=p_customer;
  delete from planeta_private.customer_consent where customer_id=p_customer;
  delete from planeta_private.chat_messages where customer_id=p_customer;
  delete from planeta_private.sales_drafts where customer_id=p_customer;
  delete from planeta_private.whatsapp_jobs where customer_id=p_customer;
  delete from planeta_private.privacy_tokens where customer_id=p_customer;
  update public.ai_handoffs set status='concluido' where customer_id=p_customer;
  update public.marketing_deliveries set status='cancelado',provider_message_id=null,lease_token=null,lease_until=null
    where customer_id=p_customer and status<>'enviado';
  update public.marketing_deliveries set provider_message_id=null where customer_id=p_customer;
  -- Compras/ledger permanecem pseudonimizados para conciliação; sem dados de contato no snapshot público.
  update public.customers set anonimizado_em=coalesce(anonimizado_em,clock_timestamp()) where id=p_customer;
  update public.lgpd_requests set status='concluido',concluido_em=clock_timestamp()
    where customer_id=p_customer and tipo='anonimizacao' and status='pendente';
  update planeta_private.privacy_receipts r set resultado=jsonb_set(r.resultado,'{status}','"concluido"')
    where r.resultado->>'protocolo' in(select id::text from public.lgpd_requests where customer_id=p_customer and tipo='anonimizacao');
  insert into public.audit_logs(acao,tabela_afetada,dados_novos)
  values('DADOS_ANONIMIZADOS','customers',jsonb_build_object('customer_id',p_customer));
  return true;
end $$;
create function public.eco_privacy_link(p_id text,p_lease uuid) returns text
language plpgsql security definer set search_path='' as $$
declare trabalho planeta_private.whatsapp_jobs; token text:=encode(extensions.gen_random_bytes(32),'hex');
begin
  trabalho:=planeta_private.job_valido(p_id,p_lease);
  perform planeta_private.limitar('privacy-link:'||trabalho.customer_id,3,900);
  insert into planeta_private.privacy_tokens(token_hash,customer_id)
  values(extensions.digest(token,'sha256'),trabalho.customer_id);
  return token;
end $$;
create function public.eco_privacy_request(p_token text,p_acao text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cliente uuid; pedido uuid; resultado jsonb; apagado boolean;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Link inválido ou expirado.' using errcode='42501'; end if;
  select customer_id into cliente from planeta_private.privacy_tokens
    where token_hash=extensions.digest(p_token,'sha256') and expires_at>now() and used_at is null for update;
  if not found then
    if p_acao='anonimizacao' then
      select r.resultado into resultado from planeta_private.privacy_receipts r
        where token_hash=extensions.digest(p_token,'sha256') and created_at>now()-interval '1 day';
      if found then return resultado; end if;
    end if;
    raise exception 'Link inválido ou expirado.' using errcode='42501';
  end if;
  perform 1 from public.customers where id=cliente for update;
  perform planeta_private.limitar('privacy:'||cliente,5,900);
  if p_acao='acesso' then
    insert into public.lgpd_requests(customer_id,tipo,status,concluido_em)
    values(cliente,'acesso','concluido',clock_timestamp()) returning id into pedido;
    select jsonb_build_object('protocolo',pedido,'perfil',jsonb_build_object('nome',d.nome,'telefone',d.telefone,'endereco',d.endereco,'created_at',d.created_at,'ultima_mensagem_em',d.last_inbound_at),
      'consentimento', (select jsonb_build_object('marketing_opt_in',marketing_opt_in,'fonte',fonte,
        'consentido_em',consentido_em,'revogado_em',revogado_em,'ads_opt_in',ads_opt_in) from planeta_private.customer_consent where customer_id=cliente),
      'pedidos',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'status',o.status,'total',o.total,
        'created_at',o.created_at,'tipo',o.tipo,'metodo_pagamento',o.metodo_pagamento,
        'pagamento_status',o.pagamento_status,'pagamento_referencia',o.pagamento_referencia,'pagamento_confirmado_em',o.pagamento_confirmado_em,
        'itens',(select jsonb_agg(jsonb_build_object('nome',produto_nome,'quantidade',quantidade,'modificadores',modificadores))
          from public.order_items where order_id=o.id))) from public.orders o where o.customer_id=cliente),'[]'),
      'fidelidade',coalesce((select jsonb_agg(jsonb_build_object('order_id',order_id,'tipo',tipo,'pontos',pontos,'created_at',created_at))
        from public.loyalty_points where customer_id=cliente),'[]'),
      'conversas',coalesce((select jsonb_agg(jsonb_build_object('role',role,'content',content,'created_at',created_at))
        from planeta_private.chat_messages where customer_id=cliente),'[]'),
      'rascunhos',coalesce((select jsonb_agg(jsonb_build_object('id',id,'itens',itens,'tipo',tipo,'metodo_pagamento',metodo_pagamento,
        'total',total,'order_id',order_id,'created_at',created_at,'expires_at',expires_at)) from planeta_private.sales_drafts where customer_id=cliente),'[]'),
      'solicitacoes',coalesce((select jsonb_agg(jsonb_build_object('id',id,'tipo',tipo,'status',status,'created_at',created_at,'concluido_em',concluido_em))
        from public.lgpd_requests where customer_id=cliente),'[]'),
      'atendimentos',coalesce((select jsonb_agg(jsonb_build_object('status',status,'created_at',created_at,'updated_at',updated_at))
        from public.ai_handoffs where customer_id=cliente),'[]'),
      'fila_mensagens',coalesce((select jsonb_agg(jsonb_build_object('texto',texto,'received_at',received_at,'status',status))
        from planeta_private.whatsapp_jobs where customer_id=cliente),'[]'),
      'campanhas',coalesce((select jsonb_agg(jsonb_build_object('campaign_id',campaign_id,'status',status,'enviado_em',enviado_em))
        from public.marketing_deliveries where customer_id=cliente),'[]')) into resultado
    from planeta_private.customer_data d where d.customer_id=cliente;
    return resultado;
  elsif p_acao in ('consentir_anuncios','revogar_anuncios') then
    update planeta_private.customer_consent set ads_opt_in=(p_acao='consentir_anuncios') where customer_id=cliente;
    if p_acao='revogar_anuncios' then
      delete from public.integration_outbox e using public.orders o where e.order_id=o.id and o.customer_id=cliente and e.status='pendente';
    end if;
    insert into public.audit_logs(acao,tabela_afetada,dados_novos) values('CONSENTIMENTO_ANUNCIOS','customers',
      jsonb_build_object('customer_id',cliente,'opt_in',p_acao='consentir_anuncios'));
    return jsonb_build_object('ok',true);
  elsif p_acao='anonimizacao' then
    insert into public.lgpd_requests(customer_id,tipo) values(cliente,'anonimizacao') returning id into pedido;
    update planeta_private.customer_consent set marketing_opt_in=false,ads_opt_in=false,revogado_em=clock_timestamp() where customer_id=cliente;
    update public.marketing_deliveries set status='cancelado',lease_token=null,lease_until=null
      where customer_id=cliente and status in ('pendente','enviando');
    update planeta_private.privacy_tokens set used_at=clock_timestamp() where customer_id=cliente;
    apagado:=planeta_private.anonimizar(cliente);
    resultado:=jsonb_build_object('protocolo',pedido,'status',case when apagado then 'concluido' else 'pendente_pedido_em_andamento' end);
    insert into planeta_private.privacy_receipts(token_hash,resultado) values(extensions.digest(p_token,'sha256'),resultado);
    return resultado;
  else raise exception 'Ação inválida.';
  end if;
end $$;
create function planeta_private.finalizar_privacidade() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.customer_id is not null and exists(select 1 from public.lgpd_requests
    where customer_id=new.customer_id and tipo='anonimizacao' and status='pendente') then
    perform planeta_private.anonimizar(new.customer_id);
  end if;
  return null;
end $$;
create trigger orders_privacy after update of status on public.orders
for each row when (new.status in ('entregue','cancelado')) execute function planeta_private.finalizar_privacidade();

create function public.eco_claim_campaign() returns jsonb
language plpgsql security definer set search_path='' as $$
declare entrega public.marketing_deliveries; campanha public.marketing_campaigns; telefone text;
begin
  update public.marketing_deliveries d set status='cancelado',lease_token=null,lease_until=null
  where d.status in ('pendente','enviando') and (
    not exists(select 1 from planeta_private.customer_consent s where s.customer_id=d.customer_id and s.marketing_opt_in)
    or exists(select 1 from public.lgpd_requests r where r.customer_id=d.customer_id and r.tipo='anonimizacao')
    or exists(select 1 from public.marketing_campaigns c where c.id=d.campaign_id and c.status='cancelada')
    or exists(select 1 from public.orders o where o.customer_id=d.customer_id and o.status='entregue'
      and o.pagamento_status='confirmado' and o.created_at>=now()-interval '15 days')
    or exists(select 1 from public.marketing_deliveries outra where outra.customer_id=d.customer_id
      and outra.id<>d.id and outra.enviado_em>now()-interval '7 days'));
  select d.* into entrega from public.marketing_deliveries d join public.marketing_campaigns c on c.id=d.campaign_id
  join planeta_private.customer_data cd on cd.customer_id=d.customer_id
  where c.status='enviando' and d.tentativas<4
    and (d.status='pendente' or (d.status='enviando' and d.lease_until<now()))
    and (d.lease_until is null or d.lease_until<now())
    and not exists(select 1 from public.orders o where o.customer_id=d.customer_id and o.status='entregue'
      and o.pagamento_status='confirmado' and o.created_at>=now()-interval '15 days')
    and not exists(select 1 from public.marketing_deliveries anterior where anterior.customer_id=d.customer_id
      and (anterior.enviado_em>now()-interval '7 days' or (anterior.status='enviando' and anterior.lease_until>now()))
      and anterior.id<>d.id)
  order by d.created_at,d.id for update of d skip locked limit 1;
  if not found then return null; end if;
  if not pg_try_advisory_xact_lock(hashtextextended('marketing:'||entrega.customer_id,0)) then return null; end if;
  perform planeta_private.limitar('marketing:global',30,60);
  update public.marketing_deliveries set status='enviando',tentativas=tentativas+1,lease_token=gen_random_uuid(),
    lease_until=now()+interval '1 minute' where id=entrega.id returning * into entrega;
  select * into campanha from public.marketing_campaigns where id=entrega.campaign_id;
  select cd.telefone into telefone from planeta_private.customer_data cd where customer_id=entrega.customer_id;
  return jsonb_build_object('id',entrega.id,'lease_token',entrega.lease_token,'telefone',telefone,
    'template_name',campanha.template_name,'template_language',campanha.template_language);
end $$;
create function public.eco_campaign_allowed(p_id uuid,p_lease uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.marketing_deliveries d
    join planeta_private.customer_consent s on s.customer_id=d.customer_id and s.marketing_opt_in
    join public.marketing_campaigns c on c.id=d.campaign_id and c.status='enviando'
    where d.id=p_id and d.lease_token=p_lease and d.status='enviando' and d.lease_until>now()
      and not exists(select 1 from public.lgpd_requests r where r.customer_id=d.customer_id and r.tipo='anonimizacao'))
$$;
create function public.eco_finish_campaign(p_id uuid,p_lease uuid,p_outbound text,p_success boolean) returns void
language plpgsql security definer set search_path='' as $$
declare campanha uuid;
begin
  update public.marketing_deliveries set status=case when p_success then 'enviado' when tentativas>=4 then 'falhou' else 'pendente' end,
    enviado_em=case when p_success then clock_timestamp() end,provider_message_id=p_outbound,
    lease_token=null,lease_until=case when p_success then null else now()+interval '5 minutes' end
  where id=p_id and lease_token=p_lease and status='enviando' returning campaign_id into campanha;
  if campanha is not null and not exists(select 1 from public.marketing_deliveries
    where campaign_id=campanha and status in ('pendente','enviando')) then
    update public.marketing_campaigns set status='concluida' where id=campanha and status='enviando';
  end if;
end $$;

-- Logística e anúncios: contratos de ponte assinada, sem fingir APIs nativas já homologadas.
create table public.fulfillment_events (
  id uuid primary key default gen_random_uuid(),
  source_id text not null references public.integration_sources(id),
  external_event_id text not null,
  order_id uuid not null references public.orders(id),
  status text not null check(status in ('despachado','entregue')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_id,external_event_id)
);
create table public.integration_outbox (
  id uuid primary key default gen_random_uuid(),
  source_id text not null references public.integration_sources(id),
  order_id uuid not null references public.orders(id),
  topic text not null check(topic='sale.completed'),
  payload jsonb not null,
  status text not null default 'pendente' check(status in ('pendente','enviado')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_id,order_id,topic)
);
alter table planeta_private.customer_consent add column ads_opt_in boolean not null default false;
create function public.eco_fulfillment(p_source text,p_event text,p_order uuid,p_status text) returns void
language plpgsql security definer set search_path='' as $$
declare pedido public.orders; evento public.fulfillment_events;
begin
  if not exists(select 1 from public.integration_sources where id=p_source and ativo and 'fulfillment'=any(scopes)) then
    raise exception 'Canal sem permissão logística.' using errcode='42501'; end if;
  if p_event is null or length(p_event) not between 1 and 200 or p_status not in ('despachado','entregue') then
    raise exception 'Evento inválido.'; end if;
  select * into evento from public.fulfillment_events where source_id=p_source and external_event_id=p_event;
  if found then
    if evento.order_id<>p_order or evento.status<>p_status then raise exception 'Conflito de idempotência logística.'; end if;
    return;
  end if;
  select * into pedido from public.orders where id=p_order for update;
  if not found or pedido.logistics_source is distinct from p_source or pedido.tipo<>'delivery' or pedido.status not in ('pronto','entregue') or pedido.pagamento_status<>'confirmado' then
    raise exception 'Pedido indisponível para logística.'; end if;
  insert into public.fulfillment_events(source_id,external_event_id,order_id,status)
  values(p_source,p_event,p_order,p_status) on conflict(source_id,external_event_id) do nothing;
  if not found then return; end if;
  if p_status='entregue' and pedido.status='pronto' then update public.orders set status='entregue' where id=p_order; end if;
end $$;
create function planeta_private.anunciar_venda() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status='entregue' and new.pagamento_status='confirmado' and exists(
    select 1 from planeta_private.customer_consent where customer_id=new.customer_id and ads_opt_in) then
    insert into public.integration_outbox(source_id,order_id,topic,payload)
    select id,new.id,'sale.completed',jsonb_build_object('event_id',new.id,'value',new.total,'currency','BRL')
      from public.integration_sources where ativo and 'ads'=any(scopes) on conflict do nothing;
  end if;
  return null;
end $$;
create trigger orders_ads after update of status on public.orders
for each row when(new.status='entregue' and old.status is distinct from new.status) execute function planeta_private.anunciar_venda();
create function public.eco_pull_events(p_source text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.integration_sources where id=p_source and ativo and 'ads'=any(scopes)) then
    raise exception 'Canal sem permissão de eventos.' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(e)) from (
    select id,topic,payload from public.integration_outbox where source_id=p_source and status='pendente' order by created_at limit 50
  ) e),'[]');
end $$;
create function public.eco_ack_event(p_source text,p_id uuid) returns void
language sql security definer set search_path='' as $$
  update public.integration_outbox set status='enviado' where id=p_id and source_id=p_source
    and exists(select 1 from public.integration_sources where id=p_source and ativo and 'ads'=any(scopes))
$$;

-- Limpeza automática quando o worker é executado (agende-o a cada minuto).
create table public.ai_handoffs (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  assigned_to uuid references public.profiles(id),
  status text not null default 'aguardando' check(status in ('aguardando','ativo','concluido')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index ai_handoff_active_idx on public.ai_handoffs(customer_id) where status<>'concluido';
create function public.eco_handoff(p_id text,p_lease uuid) returns void
language plpgsql security definer set search_path='' as $$
declare trabalho planeta_private.whatsapp_jobs;
begin
  trabalho:=planeta_private.job_valido(p_id,p_lease);
  insert into public.ai_handoffs(customer_id) values(trabalho.customer_id)
    on conflict(customer_id) where status<>'concluido' do nothing;
end $$;
create function public.assumir_atendimento(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  if planeta_private.role_atual() is null or planeta_private.role_atual() not in ('admin','caixa') then
    raise exception 'Acesso negado.' using errcode='42501'; end if;
  update public.ai_handoffs set assigned_to=auth.uid(),status='ativo' where id=p_id and status='aguardando' and assigned_to is null;
  if not found then raise exception 'Atendimento indisponível.'; end if;
end $$;
create function public.detalhes_atendimento(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cliente uuid; resultado jsonb;
begin
  select customer_id into cliente from public.ai_handoffs where id=p_id and status='ativo'
    and (planeta_private.role_atual()='admin' or (planeta_private.role_atual()='caixa' and assigned_to=auth.uid()));
  if not found then raise exception 'Acesso negado.' using errcode='42501'; end if;
  perform planeta_private.limitar('contact:'||auth.uid(),30,60);
  select jsonb_build_object('nome',nome,'telefone',telefone,'conversa',coalesce((select jsonb_agg(to_jsonb(h))
    from (select role,content,created_at from planeta_private.chat_messages where customer_id=cliente
      order by created_at desc limit 20) h),'[]')) into resultado
    from planeta_private.customer_data where customer_id=cliente;
  insert into public.audit_logs(user_id,acao,tabela_afetada,dados_novos)
    values(auth.uid(),'CONSULTA_ATENDIMENTO','customers',jsonb_build_object('customer_id',cliente,'handoff_id',p_id));
  return resultado;
end $$;

create function public.eco_cleanup() returns void
language plpgsql security definer set search_path='' as $$
begin
  update planeta_private.whatsapp_jobs set status='falhou',lease_until=null,lease_token=null
    where tentativas>=8 and status='processando' and lease_until<now();
  update public.marketing_deliveries set status='falhou',lease_until=null,lease_token=null
    where tentativas>=4 and status='enviando' and lease_until<now();
  update public.marketing_campaigns c set status='concluida' where c.status='enviando'
    and not exists(select 1 from public.marketing_deliveries d where d.campaign_id=c.id and d.status in ('pendente','enviando'));
  delete from planeta_private.chat_messages where created_at<now()-interval '7 days';
  delete from planeta_private.whatsapp_jobs where created_at<now()-interval '7 days'
    and (lease_until is null or lease_until<now());
  delete from planeta_private.privacy_tokens where expires_at<now();
  delete from planeta_private.privacy_receipts where created_at<now()-interval '1 day';
  delete from planeta_private.whatsapp_receipts where received_at<now()-interval '90 days';
  delete from planeta_private.rate_windows where updated_at<now()-interval '2 days';
  -- Clientes sem compras: elimina contatos inativos após 90 dias (sem apagar contabilidade).
  perform planeta_private.anonimizar(c.id) from public.customers c
    join planeta_private.customer_data d on d.customer_id=c.id
    where coalesce(d.last_inbound_at,d.created_at)<now()-interval '90 days'
      and not exists(select 1 from public.orders where customer_id=c.id);
end $$;

-- RLS também nos schemas privados, sem policies que permitam consultas do navegador.
do $$ declare tabela text; begin
  foreach tabela in array array['customers','integration_sources','integration_product_map','integration_events',
    'loyalty_settings','loyalty_points','marketing_campaigns','marketing_deliveries','lgpd_requests',
    'fulfillment_events','integration_outbox','ai_handoffs'] loop
    execute format('alter table public.%I enable row level security',tabela);
    execute format('create trigger z_updated_at before update on public.%I for each row execute function planeta_private.updated_at()',tabela);
  end loop;
  foreach tabela in array array['customer_data','customer_consent','privacy_tokens','privacy_receipts','rate_windows','whatsapp_receipts','whatsapp_jobs','chat_messages','sales_drafts'] loop
    execute format('alter table planeta_private.%I enable row level security',tabela);
    execute format('create trigger z_updated_at before update on planeta_private.%I for each row execute function planeta_private.updated_at()',tabela);
  end loop;
  foreach tabela in array array['integration_sources','integration_product_map','loyalty_settings','marketing_campaigns'] loop
    execute format('create policy admin_all on public.%I for all to authenticated using ((select planeta_private.role_atual())=''admin'') with check ((select planeta_private.role_atual())=''admin'')',tabela);
  end loop;
  foreach tabela in array array['customers','integration_events','loyalty_points','marketing_deliveries','lgpd_requests','fulfillment_events','integration_outbox','ai_handoffs'] loop
    execute format('create policy admin_read on public.%I for select to authenticated using ((select planeta_private.role_atual())=''admin'')',tabela);
  end loop;
  -- Snapshots só de tabelas sem PII, tokens, conversas ou endereços.
  foreach tabela in array array['customers','integration_sources','integration_product_map','loyalty_settings',
    'marketing_campaigns','lgpd_requests'] loop
    execute format('create trigger z_audit after insert or update or delete on public.%I for each row execute function planeta_private.auditar()',tabela);
  end loop;
end $$;

revoke all on public.customers,public.integration_sources,public.integration_product_map,public.integration_events,
  public.loyalty_settings,public.loyalty_points,public.marketing_campaigns,public.marketing_deliveries,
  public.lgpd_requests,public.fulfillment_events,public.integration_outbox,public.ai_handoffs,public.clientes_inativos_15_dias
from public,anon,authenticated;
grant select,insert,update,delete on public.integration_sources,public.integration_product_map,
  public.loyalty_settings,public.marketing_campaigns to authenticated;
grant select on public.customers,public.integration_events,public.loyalty_points,public.marketing_deliveries,
  public.lgpd_requests,public.fulfillment_events,public.integration_outbox,public.ai_handoffs,public.clientes_inativos_15_dias to authenticated;
create policy handoff_caixa on public.ai_handoffs for select to authenticated
using ((select planeta_private.role_atual())='caixa' and (assigned_to=(select auth.uid()) or status='aguardando'));
create policy handoff_admin_concluir on public.ai_handoffs for update to authenticated
using ((select planeta_private.role_atual())='admin') with check ((select planeta_private.role_atual())='admin');
grant update(status) on public.ai_handoffs to authenticated;
revoke all on all tables in schema planeta_private from public,anon,authenticated,service_role;
revoke all on all functions in schema planeta_private from public,anon,authenticated,service_role;
grant execute on function planeta_private.role_atual(),planeta_private.pedido_do_caixa(uuid,boolean),
  planeta_private.pedido_kds(uuid) to authenticated;

-- Nenhuma função de integração pode ser chamada com a chave pública anon ou JWT de funcionário.
do $$ declare funcao record; begin
  for funcao in select p.oid::regprocedure as assinatura from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and (p.proname like 'eco_%' or p.proname in ('contato_do_pedido','assumir_pedido','confirmar_pagamento','iniciar_campanha','assumir_atendimento','detalhes_atendimento')) loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',funcao.assinatura);
    if funcao.assinatura::text like '%eco_%' then
      execute format('grant execute on function %s to service_role',funcao.assinatura);
    else execute format('grant execute on function %s to authenticated',funcao.assinatura); end if;
  end loop;
end $$;
notify pgrst,'reload schema';
commit;
