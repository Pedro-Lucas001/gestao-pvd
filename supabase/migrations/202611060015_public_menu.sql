-- Mostruário público: somente produtos ativos e campos de apresentação.
-- Não concede acesso direto às tabelas nem permite criar pedidos ou pagamentos.
begin;
create or replace function public.public_menu()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'category', p.category,
    'description', p.description,
    'price_cents', p.price_cents,
    'image_path', p.image_path
  ) order by p.category, p.price_cents, p.name, p.id), '[]'::jsonb)
  from public.products p where p.active = true
$$;
revoke all on function public.public_menu() from public, anon, authenticated;
grant execute on function public.public_menu() to anon, authenticated;
comment on function public.public_menu() is 'Mostruário público somente leitura; exclui custos, estoque, clientes e dados de operação.';
commit;
