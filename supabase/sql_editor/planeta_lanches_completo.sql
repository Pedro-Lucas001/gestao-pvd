-- Planeta Lanches — instalação NOVA, Supabase PostgreSQL 15+.
-- Execute este arquivo inteiro no SQL Editor, como postgres.
-- NÃO combine com supabase/migrations/: o contrato abaixo usa nomes em português.
-- Nenhum dado existente será removido. Qualquer erro desfaz toda a instalação.
begin;

-- Interrompe ANTES de alterar um banco que já tenha um destes objetos.
do $$
declare objeto text;
begin
  foreach objeto in array array['profiles','categories','products','ingredients',
    'technical_sheets','orders','order_items','audit_logs','orders_gestao','order_items_gestao'] loop
    if to_regclass('public.' || objeto) is not null then
      raise exception 'Instalação interrompida: public.% já existe. Faça uma migração incremental.', objeto;
    end if;
  end loop;
  if to_regnamespace('planeta_private') is not null
     or to_regtype('public.equipe_role') is not null
     or to_regtype('public.pedido_status') is not null then
    raise exception 'Instalação interrompida: objetos desta instalação já existem.';
  end if;
end $$;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
-- A instalação normal do Supabase mantém pgcrypto em extensions.
do $$ begin
  if not exists (select 1 from pg_extension e join pg_namespace n on n.oid=e.extnamespace
    where e.extname='pgcrypto' and n.nspname='extensions') then
    raise exception 'pgcrypto deve estar no schema extensions; ajuste a extensão antes de executar.';
  end if;
end $$;

create schema planeta_private;
revoke all on schema planeta_private from public, anon, authenticated;
create type public.equipe_role as enum ('admin','caixa','cozinha');
create type public.pedido_status as enum ('pendente','preparando','pronto','entregue','cancelado');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.equipe_role not null default 'caixa',
  -- Entrada ESCRITA, nunca armazenamento de PIN: o trigger salva somente o hash privado.
  pin_code varchar(4),
  nome text not null check (length(btrim(nome)) between 1 and 120),
  ativo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pin_quatro_digitos check (pin_code is null or pin_code ~ '^[0-9]{4}$')
);
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique check (length(btrim(nome)) between 1 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete restrict,
  nome text not null check (length(btrim(nome)) between 1 and 160),
  descricao text not null default '',
  preco numeric(12,2) not null check (preco >= 0),
  imagem_url text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.ingredients (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique check (length(btrim(nome)) between 1 and 160),
  unidade_medida text not null check (length(btrim(unidade_medida)) between 1 and 30),
  quantidade_atual numeric(18,4) not null default 0 check (quantidade_atual >= 0),
  custo_unitario numeric(12,4) not null default 0 check (custo_unitario >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.technical_sheets (
  product_id uuid not null references public.products(id) on delete cascade,
  ingredient_id uuid not null references public.ingredients(id) on delete restrict,
  quantidade numeric(18,4) not null check (quantidade > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (product_id, ingredient_id)
);
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict default auth.uid(),
  status public.pedido_status not null default 'pendente',
  total numeric(12,2) not null default 0 check (total >= 0),
  metodo_pagamento text not null check (metodo_pagamento in ('pix','dinheiro','cartao')),
  tipo text not null check (tipo in ('balcao','delivery')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantidade integer not null check (quantidade between 1 and 999),
  produto_nome text not null,
  -- Snapshot do preço, definido no servidor. Nunca confie no preço enviado pelo navegador.
  preco_unitario numeric(12,2) not null check (preco_unitario >= 0),
  modificadores jsonb not null default '{}'::jsonb
    check (jsonb_typeof(modificadores)='object' and octet_length(modificadores::text)<=8192),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.audit_logs (
  id bigint generated always as identity primary key,
  -- Sem FK: mantém a identidade histórica mesmo que a conta seja removida do Auth.
  user_id uuid,
  acao text not null,
  tabela_afetada text not null,
  dados_antigos jsonb,
  dados_novos jsonb,
  data_hora timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_category_idx on public.products(category_id);
create index technical_sheets_ingredient_idx on public.technical_sheets(ingredient_id);
create index orders_user_created_idx on public.orders(user_id, created_at desc);
create index orders_kds_idx on public.orders(status, created_at);
create index order_items_order_idx on public.order_items(order_id);
create index order_items_product_idx on public.order_items(product_id);
create index audit_logs_date_idx on public.audit_logs(data_hora desc);
create index audit_logs_user_idx on public.audit_logs(user_id, data_hora desc);

create table planeta_private.pin_credentials (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  pin_hash text not null,
  falhas integer not null default 0 check (falhas between 0 and 4),
  bloqueado_ate timestamptz,
  updated_at timestamptz not null default now()
);
-- Snapshot do consumo: alterar uma ficha técnica não altera a devolução de pedidos antigos.
create table planeta_private.stock_debits (
  order_item_id uuid not null,
  ingredient_id uuid not null references public.ingredients(id) on delete restrict,
  quantidade numeric(18,4) not null check (quantidade > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(order_item_id, ingredient_id)
);

-- SECURITY DEFINER evita a recursão da policy de profiles.
create function planeta_private.role_atual() returns public.equipe_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id=auth.uid() and ativo
$$;
create function planeta_private.updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at := clock_timestamp(); return new; end $$;

create function planeta_private.salvar_pin() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.pin_code is not null then
    if new.pin_code !~ '^[0-9]{4}$' then raise exception 'PIN deve conter exatamente quatro dígitos.'; end if;
    -- BEFORE INSERT ainda não tem a linha profiles para a FK. AFTER fará a persistência.
    if tg_op='UPDATE' then
      insert into planeta_private.pin_credentials(user_id,pin_hash)
      values(new.id, extensions.crypt(new.pin_code,extensions.gen_salt('bf',10)))
      on conflict(user_id) do update set pin_hash=excluded.pin_hash,
        falhas=0,bloqueado_ate=null,updated_at=clock_timestamp();
      new.pin_code := null;
    else
      raise exception 'Crie o perfil primeiro e defina o PIN com UPDATE.';
    end if;
  end if;
  return new;
end $$;
create trigger profiles_pin before insert or update on public.profiles
for each row execute function planeta_private.salvar_pin();

-- Nenhum signup pode se promover usando raw_user_meta_data.
create function planeta_private.novo_usuario() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id,nome,role,ativo)
  values(new.id,coalesce(nullif(left(btrim(new.raw_user_meta_data->>'nome'),120),''),'Novo usuário'),'caixa',false);
  return new;
end $$;
create trigger planeta_novo_usuario after insert on auth.users
for each row execute function planeta_private.novo_usuario();
-- Contas Auth já existentes também começam SEM acesso, inclusive a primeira.
insert into public.profiles(id,nome)
select id,coalesce(nullif(left(btrim(raw_user_meta_data->>'nome'),120),''),'Novo usuário') from auth.users;

-- PIN adicional à sessão Auth: NÃO cria JWT nem substitui autenticação Supabase.
-- Retorna falha sem RAISE para que o contador não seja desfeito pelo rollback.
create function public.verificar_pin(p_pin text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cred planeta_private.pin_credentials; momento timestamptz := clock_timestamp();
begin
  if planeta_private.role_atual() is null then raise exception 'Acesso negado.' using errcode='42501'; end if;
  select * into cred from planeta_private.pin_credentials where user_id=auth.uid() for update;
  if not found then return jsonb_build_object('ok',false,'erro','PIN não configurado'); end if;
  if cred.bloqueado_ate > momento then
    return jsonb_build_object('ok',false,'bloqueado_ate',cred.bloqueado_ate);
  end if;
  if p_pin ~ '^[0-9]{4}$' and extensions.crypt(p_pin,cred.pin_hash)=cred.pin_hash then
    update planeta_private.pin_credentials set falhas=0,bloqueado_ate=null where user_id=auth.uid();
    return jsonb_build_object('ok',true);
  end if;
  update planeta_private.pin_credentials set
    falhas=case when cred.falhas=4 then 0 else cred.falhas+1 end,
    bloqueado_ate=case when cred.falhas=4 then momento+interval '3 minutes' else null end
  where user_id=auth.uid() returning * into cred;
  return jsonb_build_object('ok',false,'bloqueado_ate',cred.bloqueado_ate);
end $$;

-- Preço, autoria, transições e total são verificados mesmo nas escritas do admin.
create function planeta_private.validar_pedido() returns trigger
language plpgsql security definer set search_path = '' as $$
declare papel public.equipe_role := planeta_private.role_atual();
begin
  if tg_op='DELETE' then
    if old.status not in ('pendente','cancelado') then
      raise exception 'Pedidos em produção ou concluídos devem ser cancelados, não excluídos.';
    end if;
    return old;
  end if;
  if tg_op='INSERT' then
    if papel='caixa' then new.user_id:=auth.uid(); end if;
    new.status:='pendente'; new.total:=0;
  else
    if new.id<>old.id or new.user_id<>old.user_id or new.created_at<>old.created_at then
      raise exception 'Identificação e autoria do pedido são imutáveis.';
    end if;
    if papel='cozinha' and
       (to_jsonb(new)-'status'-'updated_at') is distinct from (to_jsonb(old)-'status'-'updated_at') then
      raise exception 'Cozinha pode alterar apenas o status.' using errcode='42501';
    end if;
    if new.total<>old.total and pg_trigger_depth()=1 then
      raise exception 'Total é calculado pelos itens.';
    end if;
    if new.status<>old.status then
      if not ((old.status='pendente' and new.status in ('preparando','cancelado'))
        or (old.status='preparando' and new.status in ('pronto','cancelado'))
        or (old.status='pronto' and new.status in ('entregue','cancelado'))) then
        raise exception 'Transição de status inválida.';
      end if;
      if papel='cozinha' and not ((old.status='pendente' and new.status='preparando')
        or (old.status='preparando' and new.status='pronto')) then
        raise exception 'Transição não autorizada para cozinha.' using errcode='42501';
      end if;
      if new.status<>'cancelado' and not exists(select 1 from public.order_items where order_id=new.id) then
        raise exception 'Pedido sem itens.';
      end if;
    end if;
  end if;
  return new;
end $$;
create trigger orders_validar before insert or update or delete on public.orders
for each row execute function planeta_private.validar_pedido();

create function planeta_private.validar_item() returns trigger
language plpgsql security definer set search_path = '' as $$
declare pedido public.orders; produto public.products; chave uuid; modificador text;
begin
  chave := case when tg_op='DELETE' then old.order_id else new.order_id end;
  select * into pedido from public.orders where id=chave for update;
  -- DELETE em cascata: o pedido já foi removido (somente pendente/cancelado permitido).
  if not found and tg_op='DELETE' then return old; end if;
  if not found then raise exception 'Pedido inexistente.'; end if;
  if pedido.status<>'pendente' and not(tg_op='DELETE' and pedido.status='cancelado') then
    raise exception 'Itens só podem ser alterados enquanto o pedido estiver pendente.';
  end if;
  if tg_op='DELETE' then return old; end if;
  -- KDS lê modificadores: somente instruções tipadas, nunca texto livre com PII.
  if jsonb_typeof(new.modificadores) is distinct from 'object' then raise exception 'Modificadores inválidos.'; end if;
  for modificador in select jsonb_object_keys(new.modificadores) loop
    if modificador='ponto' then
      if new.modificadores->>modificador not in ('bem passado','ao ponto','mal passado')
        or jsonb_typeof(new.modificadores->modificador)<>'string' then raise exception 'Ponto inválido.'; end if;
    elsif modificador not in ('cebola','tomate','alface','milho','batata_palha','queijo','bacon')
      or jsonb_typeof(new.modificadores->modificador)<>'boolean' then raise exception 'Modificador não permitido.'; end if;
  end loop;
  if tg_op='UPDATE' and (new.id<>old.id or new.order_id<>old.order_id or new.created_at<>old.created_at) then
    raise exception 'Identificação do item é imutável.';
  end if;
  select * into produto from public.products where id=new.product_id for share;
  if not found or not produto.ativo then raise exception 'Produto indisponível.'; end if;
  if tg_op='INSERT' then new.preco_unitario:=produto.preco; new.produto_nome:=produto.nome;
  elsif new.product_id<>old.product_id then new.preco_unitario:=produto.preco; new.produto_nome:=produto.nome;
  else new.preco_unitario:=old.preco_unitario; new.produto_nome:=old.produto_nome;
  end if;
  return new;
end $$;
create trigger order_items_validar before insert or update or delete on public.order_items
for each row execute function planeta_private.validar_item();

-- Serializa alterações da ficha com a venda do mesmo produto.
create function planeta_private.travar_ficha() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='UPDATE' and new.product_id<>old.product_id then
    raise exception 'Para trocar o produto, exclua e recrie a linha da ficha.';
  end if;
  if tg_op='DELETE' then
    perform 1 from public.products where id=old.product_id for update;
    return old;
  end if;
  perform 1 from public.products where id=new.product_id for update;
  return new;
end $$;
create trigger technical_sheets_lock before insert or update or delete on public.technical_sheets
for each row execute function planeta_private.travar_ficha();

-- AFTER INSERT efetua a baixa; UPDATE/DELETE reconciliam o consumo anterior.
-- Locks na mesma ordem reduzem deadlocks; falta de estoque desfaz item e baixa juntos.
create function planeta_private.baixar_estoque() returns trigger
language plpgsql security definer set search_path = '' as $$
declare item_id uuid; pedido_id uuid; produto_id uuid; unidades integer; movimento record;
begin
  if tg_op='DELETE' then
    item_id:=old.id; pedido_id:=old.order_id; produto_id:=null; unidades:=0;
  else
    item_id:=new.id; pedido_id:=new.order_id; produto_id:=new.product_id; unidades:=new.quantidade;
  end if;
  for movimento in
    with anterior as (
      select ingredient_id,quantidade from planeta_private.stock_debits where order_item_id=item_id
    ), proximo as (
      select ingredient_id,quantidade*unidades as quantidade
      from public.technical_sheets where product_id=produto_id
    )
    select coalesce(a.ingredient_id,n.ingredient_id) as ingredient_id,
      coalesce(a.quantidade,0)-coalesce(n.quantidade,0) as delta
    from anterior a full join proximo n using(ingredient_id)
    order by coalesce(a.ingredient_id,n.ingredient_id)
  loop
    update public.ingredients set quantidade_atual=quantidade_atual+movimento.delta
    where id=movimento.ingredient_id and quantidade_atual+movimento.delta>=0;
    if not found then raise exception 'Estoque insuficiente para o insumo %.',movimento.ingredient_id using errcode='23514'; end if;
  end loop;
  delete from planeta_private.stock_debits where order_item_id=item_id;
  if tg_op<>'DELETE' then
    insert into planeta_private.stock_debits(order_item_id,ingredient_id,quantidade)
    select item_id,ingredient_id,quantidade*unidades from public.technical_sheets where product_id=produto_id;
  end if;
  update public.orders set total=coalesce((select sum(quantidade*preco_unitario)
    from public.order_items where order_id=pedido_id),0) where id=pedido_id;
  return null;
end $$;
create trigger order_items_estoque after insert or update or delete on public.order_items
for each row execute function planeta_private.baixar_estoque();

create function planeta_private.devolver_estoque_cancelamento() returns trigger
language plpgsql security definer set search_path = '' as $$
declare movimento record;
begin
  for movimento in
    select d.ingredient_id,sum(d.quantidade) as quantidade
    from planeta_private.stock_debits d join public.order_items i on i.id=d.order_item_id
    where i.order_id=new.id group by d.ingredient_id order by d.ingredient_id
  loop
    update public.ingredients set quantidade_atual=quantidade_atual+movimento.quantidade where id=movimento.ingredient_id;
  end loop;
  delete from planeta_private.stock_debits d using public.order_items i
    where i.id=d.order_item_id and i.order_id=new.id;
  return null;
end $$;
create trigger orders_cancelar_estoque after update of status on public.orders
for each row when (old.status is distinct from new.status and new.status='cancelado')
execute function planeta_private.devolver_estoque_cancelamento();

create function planeta_private.auditar() returns trigger
language plpgsql security definer set search_path = '' as $$
declare antes jsonb; depois jsonb; operacao text:=tg_op;
begin
  if tg_op<>'INSERT' then antes:=to_jsonb(old); end if;
  if tg_op<>'DELETE' then depois:=to_jsonb(new); end if;
  -- PIN nunca entra na trilha, nem como hash.
  if tg_table_name='profiles' then antes:=antes-'pin_code'; depois:=depois-'pin_code'; end if;
  if tg_table_name='orders' then
    if tg_op='UPDATE' then
      if old.status<>new.status and new.status='cancelado' then operacao:='PEDIDO_CANCELADO'; end if;
    end if;
  end if;
  insert into public.audit_logs(user_id,acao,tabela_afetada,dados_antigos,dados_novos)
  values(auth.uid(),operacao,tg_table_name,antes,depois);
  return null;
end $$;
create function planeta_private.bloquear_auditoria() returns trigger
language plpgsql set search_path = '' as $$
begin raise exception 'Auditoria imutável: UPDATE, DELETE e TRUNCATE proibidos.' using errcode='42501'; end $$;
create trigger audit_logs_imutavel before update or delete or truncate on public.audit_logs
for each statement execute function planeta_private.bloquear_auditoria();

-- Toda tabela operacional recebe timestamp e auditoria automáticos.
do $$
declare tabela text;
begin
  foreach tabela in array array['profiles','categories','products','ingredients','technical_sheets','orders','order_items'] loop
    execute format('create trigger z_updated_at before update on public.%I for each row execute function planeta_private.updated_at()',tabela);
    execute format('create trigger z_audit after insert or update or delete on public.%I for each row execute function planeta_private.auditar()',tabela);
  end loop;
end $$;
create trigger pin_updated_at before update on planeta_private.pin_credentials
for each row execute function planeta_private.updated_at();
create trigger debits_updated_at before update on planeta_private.stock_debits
for each row execute function planeta_private.updated_at();
-- audit_logs possui updated_at, mas jamais pode receber UPDATE: a imutabilidade prevalece.

-- A policy de itens não consulta colunas financeiras com privilégios do cliente.
create function planeta_private.pedido_do_caixa(p_id uuid, p_pendente boolean) returns boolean
language sql stable security definer set search_path = '' as $$
  select planeta_private.role_atual()='caixa' and exists (
    select 1 from public.orders where id=p_id and user_id=auth.uid()
      and (not p_pendente or status='pendente'))
$$;

-- RLS: proteção adicional aos GRANTs. Nenhum acesso anônimo ao banco operacional.
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.ingredients enable row level security;
alter table public.technical_sheets enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.audit_logs enable row level security;
alter table planeta_private.pin_credentials enable row level security;
alter table planeta_private.stock_debits enable row level security;

-- Admin em todas as tabelas de operação; as validações de negócio continuam válidas.
do $$ declare tabela text; begin
  foreach tabela in array array['profiles','categories','products','ingredients','technical_sheets','orders','order_items'] loop
    execute format('create policy admin_all on public.%I for all to authenticated using ((select planeta_private.role_atual())=''admin'') with check ((select planeta_private.role_atual())=''admin'')',tabela);
  end loop;
end $$;
create policy profile_proprio on public.profiles for select to authenticated
using (id=(select auth.uid()));
create policy categories_caixa on public.categories for select to authenticated
using ((select planeta_private.role_atual())='caixa');
create policy products_caixa on public.products for select to authenticated
using ((select planeta_private.role_atual())='caixa');
create policy orders_caixa_ler on public.orders for select to authenticated
using ((select planeta_private.role_atual())='caixa' and user_id=(select auth.uid()));
create policy orders_caixa_inserir on public.orders for insert to authenticated
with check ((select planeta_private.role_atual())='caixa' and user_id=(select auth.uid()));
create policy orders_cozinha_ler on public.orders for select to authenticated
using ((select planeta_private.role_atual())='cozinha');
create policy orders_cozinha_status on public.orders for update to authenticated
using ((select planeta_private.role_atual())='cozinha')
with check ((select planeta_private.role_atual())='cozinha');
create policy items_caixa_ler on public.order_items for select to authenticated
using (planeta_private.pedido_do_caixa(order_id,false));
create policy items_caixa_inserir on public.order_items for insert to authenticated
with check (planeta_private.pedido_do_caixa(order_id,true));
-- KDS recebe somente os campos seguros concedidos abaixo, sem preço nem pagamento.
create policy items_cozinha_ler on public.order_items for select to authenticated
using ((select planeta_private.role_atual())='cozinha');
create policy audit_admin_ler on public.audit_logs for select to authenticated
using ((select planeta_private.role_atual())='admin');
-- Sem policies de escrita nos logs e nas tabelas privadas.

-- TODOS usam o papel SQL authenticated; GRANT por coluna não distingue profiles.role.
-- A base orders é consultável SOMENTE nos campos seguros, inclusive via Realtime.
-- Admin/caixa consultam os demais campos pela view abaixo, filtrada no servidor.
create view public.orders_gestao with (security_barrier=true) as
select o.* from public.orders o
where planeta_private.role_atual()='admin'
   or (planeta_private.role_atual()='caixa' and o.user_id=auth.uid());
create view public.order_items_gestao with (security_barrier=true) as
select i.* from public.order_items i
where planeta_private.role_atual()='admin'
   or planeta_private.pedido_do_caixa(i.order_id,false);
comment on view public.orders_gestao is
  'Visão financeira com filtro explícito por auth.uid/role. Não habilitar security_invoker: a base tem SELECT limitado por coluna.';

-- Permissão SQL de coluna também protege escritas SEM mudança de valor, evitando
-- que uma conta da cozinha descubra o método de pagamento tentando valores conhecidos.
-- Admin edita pela visão; o trigger verifica cargo e mantém todas as regras da tabela.
create function planeta_private.editar_pedido_gestao() returns trigger
language plpgsql security definer set search_path='' as $$
declare registro public.orders; atribuicoes text; retorno jsonb;
begin
  if planeta_private.role_atual() is distinct from 'admin' then
    raise exception 'Somente admin pode editar a visão de gestão.' using errcode='42501';
  end if;
  registro:=jsonb_populate_record(null::public.orders,to_jsonb(new));
  -- Identificadores vêm do catálogo PostgreSQL, nunca de entrada do cliente.
  select string_agg(format('%I=($1).%I',attname,attname),',' order by attnum) into atribuicoes
    from pg_attribute where attrelid='public.orders'::regclass and attnum>0 and not attisdropped;
  execute 'update public.orders set '||atribuicoes||' where id=$2 returning to_jsonb(orders.*)'
    into retorno using registro,old.id;
  if retorno is null then return null; end if;
  return jsonb_populate_record(new,retorno);
end $$;
create trigger orders_gestao_update instead of update on public.orders_gestao
for each row execute function planeta_private.editar_pedido_gestao();

revoke all on public.profiles,public.categories,public.products,public.ingredients,
  public.technical_sheets,public.orders,public.order_items,public.audit_logs,
  public.orders_gestao,public.order_items_gestao from public,anon,authenticated;
grant usage on schema public to authenticated;
grant select,insert,update,delete on public.profiles,public.categories,public.products,
  public.ingredients,public.technical_sheets to authenticated;
grant insert,delete on public.orders to authenticated;
grant update(status) on public.orders to authenticated;
grant insert,update,delete on public.order_items to authenticated;
grant select(id,status,created_at,updated_at) on public.orders to authenticated;
grant select(id,order_id,product_id,produto_nome,quantidade,modificadores,created_at,updated_at)
  on public.order_items to authenticated;
grant select on public.orders_gestao,public.order_items_gestao,public.audit_logs to authenticated;
grant update on public.orders_gestao to authenticated;
-- Evita que defaults de privilégios do projeto exponham segredos ou funções internas.
revoke all on all tables in schema planeta_private from public,anon,authenticated;
revoke all on all functions in schema planeta_private from public,anon,authenticated;
-- Necessária às expressões de RLS, sem conceder USAGE no schema privado.
grant execute on function planeta_private.role_atual(),planeta_private.pedido_do_caixa(uuid,boolean) to authenticated;
revoke all on function public.verificar_pin(text) from public,anon,authenticated;
grant execute on function public.verificar_pin(text) to authenticated;

-- Realtime: coluna financeira NÃO entra no stream, independentemente do assinante.
-- A lista vale para toda a publicação, inclusive para admin/caixa: recarregue a view
-- orders_gestao após um evento se precisar atualizar valores financeiros.
do $$ begin
  if not exists(select 1 from pg_publication where pubname='supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;
alter publication supabase_realtime add table
  public.orders (id,status,created_at,updated_at),
  public.order_items (id,order_id,product_id,produto_nome,quantidade,modificadores,created_at,updated_at);
-- Replica identity DEFAULT mantém apenas a PK em old nas exclusões; não usar FULL,
-- pois a publicação exclui colunas financeiras.
alter table public.orders replica identity default;
alter table public.order_items replica identity default;

notify pgrst, 'reload schema';
commit;

-- PASSO MANUAL APÓS A INSTALAÇÃO (SQL Editor, usuário postgres):
-- Crie primeiro a conta em Authentication > Users e substitua o UUID abaixo.
-- update public.profiles set role='admin',ativo=true,nome='Administrador',pin_code='1234'
-- where id='UUID-DA-SUA-CONTA';
-- Escolha um PIN próprio; 1234 acima é apenas exemplo, não uma credencial criada.
-- Nunca coloque service_role no frontend.
