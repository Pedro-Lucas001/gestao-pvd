# Planeta Lanches · operação e gestão

React + Supabase (PostgreSQL/Auth/Realtime), com interface cinza-aço e laranja-fogo. Os módulos estão conectados a dados reais do projeto quando configurado; sem Supabase, a aplicação exibe uma prévia visual e bloqueia transações.

## Módulos implementados no código

- **PDV:** catálogo, quantidades, modificadores inline, preços calculados no banco, turno individual, sangria/suprimento, fechamento e retomada de pedidos pendentes.
- **KDS:** tickets por setor, sem dados de contato nem valores; cores por espera, atualizações Realtime e ressincronização/polling.
- **Autoatendimento:** links/QRs revogáveis para mesas/delivery, catálogo público seguro, criação idempotente, acompanhamento pessoal e Pix com valor do pedido.
- **Gestão:** edição de produtos, ingredientes/custos, saldos, fichas técnicas e consumo por modificador; descontos, estornos integrais, equipe, terminais, delivery e auditoria.
- **Relatórios:** receita confirmada, horários de pico, descontos, margens estimadas pela receita atual, tempos por setor e alertas de estoque.
- **WhatsApp oficial:** webhook assinado para texto, FAQ determinístico, atribuição de atendimento, resposta do operador e notificações por status com consentimento/janela/templates, fila com lease e retry. Exige habilitação da API oficial; o aplicativo Business sozinho não é essa API.

## Segurança avançada

Auditoria automática e append-only no PostgreSQL registra usuário/origem, ação, data, valor, justificativa e quantidade de estoque. Usuários da aplicação, inclusive admin e service role, não têm rota/permissão de editar, apagar ou truncar os logs; triggers bloqueiam DML comum até do dono da tabela. O proprietário do banco continua tendo poder de alterar o schema — proteção contra esse privilégio exige controles externos, conforme [docs/security.md](docs/security.md).

Terminais são cadastrados por admin e identificados por token aleatório, mantido ao trocar de operador. **Cinco PINs incorretos consecutivos no mesmo terminal bloqueiam por três minutos**, com contador no banco. PINs são hashes bcrypt privados. PDV/KDS e áreas autenticadas bloqueiam após **10 minutos sem entrada real do usuário**; polling/Realtime não mantêm o terminal destravado. Ao bloquear, o conteúdo sensível é desmontado da tela. Dados de contato do delivery têm RLS separada: cozinha não acessa/exporta; o responsável vê apenas pedidos pagos em andamento.

## Pix da conta Nubank física

Conforme a configuração informada pela loja, o código suporta **BR Code/QR estático com o valor exato**, usando a chave cadastrada nos segredos do servidor. Não é Pix Cob dinâmico nem uma API bancária. Não há expiração bancária automática, consulta de saldo, comprovação automática ou transferência de devolução.

O **administrador confere o crédito no extrato**, informa uma referência bancária única e a justificativa. Só então o banco libera cozinha e baixa insumos. A mesma referência normalizada não pode pagar dois pedidos. Devolução Pix deve ser feita no app Nubank e depois registrada; gerar QR ou solicitar estorno não equivale a receber/devolver dinheiro. Para automação financeira real é necessário contratar/acessar um PSP com API homologada. **TEF permanece indisponível**, pois maquininha/serviço não foram informados.

## Executar

Requer Node.js 22.12+ ou 20.19+:

```sh
npm ci
npm run dev
```

Sem variáveis abre a prévia; não cria pedidos reais. Para operar, crie o projeto Supabase, aplique **todas as migrações em ordem**, carregue o seed, crie o admin e configure `.env.local` usando `.env.example`. As Edge Functions usam segredos próprios exemplificados em `supabase/.env.example`; **nunca coloque chave bancária, service role, PIN, senha ou tokens em VITE_***.

[Passo a passo de ativação](docs/activation.md) · [Arquitetura](docs/architecture.md) · [Segurança e privacidade](docs/security.md) · [Deploy/pooler/backup](docs/deploy.md).

## SQL Editor solicitado: contrato independente em português

[Instalação e diferenças de contrato](supabase/sql_editor/README.md) · [Partes 5/6, IA, fidelidade, gateways e LGPD](supabase/sql_editor/ECOSSISTEMA.md).

Os dois arquivos de `supabase/sql_editor/` são uma **alternativa de esquema**, com os nomes em português pedidos. Não aplique junto com `supabase/migrations/`: o frontend operacional acima usa campos/cargos em inglês. Os endpoints `eco-*` e o portal estático dessa pasta usam exclusivamente o contrato em português; URL/API key não adaptam o frontend automaticamente. Essa separação evita sobrescrever um projeto existente.

## Validar

```sh
npm run validate
npm run test:db
bash scripts/test-sql-editor.sh
deno check supabase/functions/*/index.ts
deno test supabase/functions/_shared/*_test.ts
```

O banco de teste é PostgreSQL real descartável, sem portas publicadas nem dados reais. Testes opcionais de navegador em [tests/README.md](tests/README.md) usam Auth/REST simulados e não substituem homologação do Supabase hospedado ou da Meta.

Os 47 produtos do cardápio estão no seed; novas alterações usam o banco. Não foram inventados custos, estoque, combos, receitas ou taxas de entrega. Configure as condições de entrega e o catálogo real antes de divulgar links. Consumo de modificadores requer regras cadastradas; sem regra, vale a ficha padrão. Saldo negativo não apaga uma venda já paga: gera alerta para conferência.

O histórico Python/SQLite foi preservado, mas não é o backend desta versão. Dados antigos não foram apagados nem migrados automaticamente. Nenhuma conta bancária, conta Meta, projeto Supabase ou implantação hospedada foi criada/ativada por estes comandos.
