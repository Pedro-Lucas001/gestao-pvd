# Situação da ativação — 07/11/2026

Projeto Supabase confirmado: **Planeta-Lanches** (`qhtcyqsmjuwlhsrzjhqp`).
Projeto Vercel: **gestao-pvd**. Domínio de produção: `https://gestao-pvd.vercel.app`.

## Conferido diretamente

- O banco possui oito tabelas antigas, todas com contagem exata de zero registros:
  profiles, ingredients, products, technical_sheets, orders, order_items,
  audit_logs e customers. Não há usuários Auth, buckets nem Edge Functions.
- É um terceiro contrato, com `profiles.full_name`, `pin_code` e `products.price`;
  os indicadores antigos de `name`/`nome` não o identificavam.
- O frontend atual espera 001–018, ausentes nesse projeto. O instalador de banco
  vazio recusa corretamente essa situação.
- A Vercel tem uma publicação READY da main anterior e nenhuma variável de
  ambiente de projeto cadastrada na consulta realizada.

## Preparado e testado

PR de correções: https://github.com/Pedro-Lucas001/gestao-pvd/pull/11

- Deno separado de Vite/PWA/Rollup, runtime fixado e dependências com lockfile.
- Admin retoma o bloqueio com senha; senha incorreta mantém o bloqueio.
- Formulário único de criação da equipe e informações de integrações atualizadas.
- Instaladores gerados das fontes, sem fixtures nem criação automática de admin.
- Transição específica preservando tabelas/funções antigas em schema privado,
  recusando qualquer registro/conta/bucket ou estrutura diferente.
- Lint, 17 testes Node, build, testes SQL operacionais e testes Deno aprovados.
  Teste de navegador aprovado com Auth/REST simulados, incluindo senha incorreta,
  retomada do admin, equipe, caixa, offline, retry e isolamento de rotas.

## Ainda não aplicado

A revisão automática rejeitou a aplicação remota por exigir autorização explícita
para a migração específica que move objetos legados e instala o contrato atual.
Uma consulta posterior confirmou as oito tabelas originais, nenhum schema de
arquivo criado e `public_menu()` ainda ausente.

SQL concreto para revisão: [03_transicao_legado_vazio.sql](../supabase/activation/03_transicao_legado_vazio.sql).
Ele preserva objetos, não apaga registros e deixa pedidos e entrega pausados.
Ainda assim, muda nomes de acesso da estrutura anterior e não deve ser aplicado
se houver outra aplicação utilizando aqueles objetos.

Depois da autorização: aplicar a transição, conferir catálogo/RLS, configurar
as variáveis públicas de produção na Vercel, publicar as funções corretas e
publicar o frontend. Não apontar previews automaticamente para o banco da loja.

## Ações que dependem da conta da loja

Criar a primeira conta pelo painel Auth com senha escolhida pelo responsável,
ativar o UUID correto e cadastrar os terminais. As ferramentas conectadas não
oferecem criação de contas Auth nem cadastro de segredos das Edge Functions.

Configuração base no painel de segredos das funções:

```dotenv
APP_ALLOWED_ORIGINS=https://gestao-pvd.vercel.app
PUBLIC_SITE_URL=https://gestao-pvd.vercel.app
```

Configurar também segredos próprios de rate limit/worker e, para cada serviço
escolhido, as credenciais de Pix/Mercado Pago, Meta e OpenAI. Valores privados
somente nos painéis seguros; nunca no chat ou em VITE_*. O exemplo completo está
em [supabase/.env.example](../supabase/.env.example).

Pix manual exige conferência do crédito; cartão online exige homologação do
provedor. WhatsApp exige número/token/templates e agendamento. IA exige chave,
limites e consentimento. Nenhum serviço externo pago foi ativado, nenhum valor
foi cobrado e nenhuma mensagem foi enviada nesta preparação.
