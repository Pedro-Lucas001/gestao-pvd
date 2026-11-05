# Validação da versão Supabase

## Frontend

```sh
npm run validate
```

Executa ESLint, seis testes de regras puras com o runner nativo Node e build Vite. Os testes verificam centavos sem valores ambíguos, pontos de carne mutuamente exclusivos, idempotency key/corpo sem preço enviado pelo cliente, limites de cores do KDS e matriz de acesso às rotas e respostas de RPC sem ambiguidade.

## PostgreSQL / RLS

```sh
npm run test:db
```

Requer Docker local e baixa a imagem oficial PostgreSQL 17 Alpine. Cria um banco **descartável**, sem portas publicadas, sem volumes e sem dados reais, e o remove ao terminar. Não aceita `DATABASE_URL` de produção. `supabase/tests/bootstrap.sql` é apenas um fixture local do contrato de Auth; **nunca aplicar esse arquivo em Supabase real**.

Aplica migration e seed e testa com `SET ROLE authenticated/anon/service_role`: autoescalada de cargo negada, dados financeiros invisíveis à cozinha, custos invisíveis ao caixa, isolamento entre caixas e setores, PIN nulo/incorreto/bloqueio, lease de sessão, total no banco mesmo com preço adulterado, retry sem duplicação, exclusões/modificadores, dinheiro, validação de valor Pix no contrato SQL, eventos repetidos/alterados, baixa por ficha uma única vez, transições de tickets, conclusão e fechamento de caixa idempotentes. Exceções inesperadas ou qualquer asserção falsa falham o comando.

Isso testa PostgreSQL real, **não** a implementação completa do Supabase Auth, o PostgREST hospedado, WebSockets em rede ou um gateway financeiro.

## Navegador (opcional)

Com Playwright Python e Chromium instalados:

```sh
python3 tests/ui_smoke.py
```

Inicia Vite em portas descartáveis. Exercita a prévia real e, em seguida, usa **Auth/REST simulados explicitamente** para validar roteamento por cargo, bloqueio offline, retenção do corpo/chave após falha e a tela de pagamento em dinheiro. A segurança dessas simulações não substitui os testes RLS. As capturas são salvas em `/tmp/planeta-pdv-desktop.png` e `/tmp/planeta-pdv-mobile.png`. `CHROMIUM_PATH` seleciona outro executável.

## Edge Functions

Com Deno instalado:

```sh
deno check supabase/functions/payment-intent/index.ts supabase/functions/provider-webhook/index.ts
deno test supabase/functions/_shared/http_test.ts
```

Verifica tipos/imports e três testes de integridade do corpo bruto, limite de payload e gateway fail-closed. Nenhum deploy ou pagamento é executado. Os adaptadores falham fechados enquanto não houver integração real.

## Histórico

`test_server.py` e `test_menu.py` são testes da versão anterior Python/SQLite e catálogo estático. Foram mantidos como referência; não são a validação de backend da stack atual.

## Ainda exige projeto real

Homologar Supabase Auth com contas reais, leases com JWT emitido pelo serviço, migrations/seed em staging, streaming Realtime/reconexão entre dois terminais, pooler hospedado e limites do plano, deploy Vercel com SPA/CSP, Pix sandbox, TEF homologado, assinatura/replay e reconciliação dos webhooks. Esses itens não foram declarados aprovados por testes locais.
