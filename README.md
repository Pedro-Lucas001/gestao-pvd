# Planeta Lanches · PDV + Supabase

React com visual **cinza-aço e laranja-fogo**, Supabase Auth/PostgreSQL/RLS e fundação do KDS com Realtime. Esta entrega contém a arquitetura, o esquema relacional e o código inicial do **Módulo 1 — frente de caixa**; não é uma implantação pronta de todos os módulos descritos.

## Começar

Node.js 22.12+ (ou 20.19+):

```sh
npm ci
npm run dev
```

Sem variáveis Supabase, a aplicação abre uma **prévia visual**, com os 47 produtos reais do cardápio, imagens ilustrativas, filtros, carrinho e modificadores inline. Nenhum login, pedido ou pagamento real é simulado. Combos aparecem como categoria vazia até cadastro de combinações reais.

Para operar: crie um projeto Supabase, siga [docs/deploy.md](docs/deploy.md), aplique as migrações e seed, crie as contas e configure os valores públicos de `.env.example` em `.env.local`. Com Supabase configurado, os acessos são individuais:

- **Admin:** PDV, KDS e áreas de gestão protegidas; criação de perfis/ativação/PINs. As telas de estoque/relatórios são fundações documentadas, não módulos completos.
- **Caixa:** somente PDV, turno próprio e próprios pedidos. E-mail/senha + PIN pessoal de 4 dígitos para destravar o terminal, com limite de tentativas e lease de 15 min no servidor.
- **Cozinha:** somente KDS e tickets do seu setor, sem valores financeiros.

O PostgreSQL calcula os totais e valida modificadores; não aceita o preço informado pelo navegador. Confirmação manual de **dinheiro** libera o pedido; **Pix e TEF ainda exigem provedor e homologação**, e os adaptadores falham fechados. Pedidos e tentativas usam idempotência para retry sem duplicação. Offline preserva o rascunho e bloqueia envios/pagamentos até reconectar.

## Estrutura

```text
src/auth/              sessão, PIN e proteção de rotas por cargo
src/pdv/               catálogo, carrinho, personalização, turno e pagamentos
src/kds/               tickets por setor, cores por tempo e ressincronização
src/components/        Error Boundaries e detecção de rede
src/lib/               cliente Supabase, operações puras e monitoramento
supabase/migrations/   tabelas, RLS, grants e RPCs transacionais
supabase/functions/    contratos de Pix/TEF e webhook fail-closed
supabase/seed.sql      47 produtos; sem estoque/custos/receitas inventados
supabase/tests/        testes de autorização e transações em PostgreSQL real
docs/                  arquitetura, implantação e consultas de analytics
```

- [Arquitetura e modelo relacional](docs/architecture.md), com limites, RLS, idempotência, PIN, estoque, Realtime, autoatendimento e WhatsApp.
- [Implantação e variáveis staging/production](docs/deploy.md), Vercel, pooler, backups e monitoramento.
- [Consultas de analytics para admin](docs/analytics.sql): picos de horário, margem por ficha e gargalos.
- [Testes e evidências](tests/README.md).

## Validar e compilar

```sh
npm run validate
npm run test:db
npm run build
```

`test:db` exige Docker local e usa PostgreSQL descartável sem portas publicadas. Não usa credenciais nem banco da loja. Não substitui homologação em Supabase hospedado. O frontend pode ser publicado na Vercel com a configuração versionada, mas nenhum serviço foi publicado automaticamente.

A versão anterior Python/SQLite e seus testes permanecem no histórico/arquivos para consulta; **não fazem parte do backend ativo desta versão**. Não execute `server.py` para usar o PDV Supabase. Os usuários, pedidos e saldos antigos não foram migrados nem apagados. A migração de dados exige um procedimento separado com conferência de saldos e contas. O catálogo estático anterior foi mantido para a prévia; no modo real, o catálogo vem do PostgreSQL, com o seed do cardápio e as bebidas 200 ml confirmadas pela loja.
