# Validação

## Frontend

`npm run validate`: ESLint, testes Node e build Vite. Verificam centavos sem valores ambíguos, modificadores exclusivos, chaves/corpo de retry sem preço vindo do cliente, limiares KDS, matriz de rotas, normalização de RPC, 10 min de inatividade com relógio monotônico e abort de requisição sem perder headers de autenticação.

## PostgreSQL real / RLS / auditoria

`npm run test:db` exige Docker local. Sobe PostgreSQL 17 Alpine descartável sem portas publicadas, aplica todas as migrations/seed e duas suites SQL, removendo o container ao final. Não usa banco/credenciais da loja. `supabase/tests/bootstrap.sql` é apenas fixture de Auth para PostgreSQL vazio; nunca aplicar em Supabase real.

`rls.sql` cobre: autoescalada de cargo, grants mínimos, custos/financeiro invisíveis à cozinha, isolamento entre caixas/setores, PIN, cadastro de terminal, total canônico mesmo com preço adulterado, idempotência, gate de pagamento, fichas e baixa única, transições, fechamento e eventos de PSP (apenas contrato SQL).

`advanced.sql` cobre: logs imutáveis para admin/service/dono em DML normal, justificativas/valores/quantidades automáticas, cinco erros em contas diferentes no mesmo terminal e lockout exato de 180 s, terminal forjado negado, lease expirada sem revive por heartbeat, QR público e tracking sem contatos, privacidade RLS de delivery antes/depois da atribuição/pagamento/entrega, descontos, sangria idempotente, receita por modificador, relatório, Pix manual/refund, referência bancária única normalizada, crédito tardio sem reabrir KDS e anonimização.

Asserções falsas e erros inesperados preservam exit status de falha. Os testes usam roles reais `anon/authenticated/service_role`, mas **não** simulam a validação criptográfica hospedada do Supabase Auth: `auth.uid/auth.jwt` são fixtures locais. Não são homologação do PostgREST/Realtime hospedado ou teste de carga de pico.

## Funções

```sh
deno check supabase/functions/*/index.ts
deno test supabase/functions/_shared/*_test.ts
```

Testam corpo bruto e limite de payload, gateway sem configuração recusado, BR Code estático (valor/CRC/campos), nenhuma aprovação bancária falsa, TEF indisponível, HMAC correto/alterado/ausente e FAQ determinístico. Chaves/emails de teste não são credenciais reais. Nenhum Pix, estorno, mensagem ou deploy real é executado.

## Navegador

Com Playwright Python e Chromium:

```sh
python3 tests/ui_smoke.py
```

Inicia Vite em portas descartáveis e valida a prévia e Auth/REST **explicitamente simulados**. Verifica 47 produtos, modificadores inline, celular, bloqueio offline, retry com mesmo corpo/chave, pagamento dinheiro, auto-lock em 10 min, ausência do formulário sensível atrás do bloqueio, PIN para retomar, persistência do bloqueio de admin após reload, redirecionamento por cargo e checkout público que não marca Pix indisponível como pago. Capturas em `/tmp/planeta-pdv-desktop.png`, `/tmp/planeta-pdv-mobile.png` e `/tmp/planeta-idle-lock.png`.

## Ainda exige serviços reais

Aplicar/homologar staging Supabase com JWTs reais, Realtime entre terminais, pooler/plano, Vercel/TLS/CSP, QR e conta Nubank real com conferência de crédito/devolução, API Meta/número/permissões/templates/janela, cron autenticado e restauração de backup. Sentry precisa de DSN/domínio. TEF precisa de equipamento/serviço homologado. Esses resultados não são declarados aprovados por mocks ou testes locais.

`test_server.py/test_menu.py` são do histórico Python/SQLite e catálogo estático, não o backend ativo.

## Contrato independente do SQL Editor

`bash scripts/test-sql-editor.sh` cria um PostgreSQL descartável separado para os scripts em português, sem misturar com as migrações do frontend em inglês. Testa o esquema base e as partes 5/6, inclusive pagamento antes do KDS, fidelidade, consentimento e direitos do titular.

`python3 tests/privacy_portal_smoke.py` usa Playwright/Chromium e API simulada para validar token no fragmento, ausência de sessão de funcionário/localStorage, download pessoal, confirmação de exclusão e tamanho móvel. Não conecta ao Supabase real e não envia mensagens nem pagamentos.
