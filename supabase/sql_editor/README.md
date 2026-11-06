# Instalação independente no SQL Editor

Abra `planeta_lanches_completo.sql`, copie **todo** o conteúdo para o SQL Editor do Supabase e execute como `postgres`. O arquivo usa uma transação única e interrompe a execução se alguma das tabelas já existir. Faça backup antes de qualquer migração em produção.

Este é o contrato em português solicitado (`role = admin/caixa/cozinha`, `nome`, `preco`, `quantidade`, etc.). **Não aplique junto com `supabase/migrations/`**: aquela sequência pertence ao frontend atual do repositório, que utiliza outro contrato (`cashier/kitchen`, campos em inglês). Conectar URL e chave não adapta automaticamente as consultas do frontend. Se as migrações anteriores já foram aplicadas, use uma migração incremental para preservar os dados; este arquivo abortará sem sobrescrevê-los.

Para as partes 5 e 6, execute depois `planeta_lanches_ecossistema.sql`. Ele adiciona clientes protegidos, IA/WhatsApp, gateways, fidelidade, campanhas, governança e uma barreira de pagamento antes da cozinha. Consulte [ECOSSISTEMA.md](./ECOSSISTEMA.md) para os endpoints e a ativação. **Nenhum dos arquivos foi aplicado ao seu Supabase por este trabalho.**

## Primeira conta e PIN

1. Crie a conta em **Authentication → Users**. O trigger cria o perfil como caixa **inativo**, ignorando qualquer cargo enviado nos metadados do cadastro.
2. No SQL Editor, promova a conta usando seu UUID real:

   ```sql
   update public.profiles
   set role = 'admin', ativo = true, nome = 'Seu nome'
   where id = 'UUID-REAL-DA-CONTA';
   ```

3. Para configurar o PIN, faça `UPDATE public.profiles SET pin_code = 'SEU_PIN' WHERE id = 'UUID-REAL';`, substituindo `SEU_PIN` por quatro dígitos. O campo é uma entrada de escrita: seu valor fica `NULL`, e somente um hash bcrypt é guardado no schema privado. Não existe PIN padrão criado pelo script.

O RPC `verificar_pin(p_pin)` exige uma sessão Supabase Auth ativa e verifica apenas o PIN do próprio usuário. Cinco falhas bloqueiam essa conta por três minutos. Ele **não emite sessão Auth**, não implementa bloqueio por terminal, nem aplica sozinho a tela de inatividade de dez minutos. O bloqueio adicional da interface exige integração com o frontend; este SQL independente não substitui os módulos de terminal existentes na outra sequência de migrações.

## Consultas e permissões

Todos os usuários do frontend usam o papel PostgreSQL `authenticated`. Como RLS filtra linhas, sem esconder colunas, as consultas seguem estes contratos:

| Uso | Origem | Campos/permissão |
| --- | --- | --- |
| KDS/pedidos seguros | `orders` | SELECT explícito de `id,status,created_at,updated_at`; cozinha pode UPDATE somente de status |
| KDS/itens seguros | `order_items` | SELECT explícito de `id,order_id,product_id,produto_nome,quantidade,modificadores,created_at,updated_at`; cozinha não escreve |
| Gestão financeira | `orders_gestao` e `order_items_gestao` | SELECT completo; admin vê tudo, caixa vê somente seus pedidos; cozinha recebe zero linhas |
| Cadastro/estoque/fichas | Tabelas correspondentes | Escrita admin; caixa lê somente produtos/categorias |
| Auditoria | `audit_logs` | SELECT admin; inserções apenas por triggers; ninguém da aplicação altera/apaga/inventa registros |

A criação de pedidos e a escrita de itens usam as tabelas base. UPDATE direto em `orders` permite apenas `status`; admin edita os demais campos por `orders_gestao`, cujo trigger confere o cargo e preserva as regras. Caixa não pode atualizar pela visão financeira. Essa restrição também impede sondar pagamentos com UPDATE sem mudança de valor. Não solicite `.select('*')` ou `RETURNING *` nessas escritas: as colunas financeiras não têm SELECT direto, inclusive para admin. Consulte as visões financeiras após a escrita. Exemplo:

```js
await supabase.from('orders').insert({ metodo_pagamento: 'pix', tipo: 'balcao' })
const { data } = await supabase.from('orders_gestao').select('*')
// Para ter o ID imediatamente: insert(...).select('id').single()
```

O cliente pode fornecer UUIDs dos itens para idempotência. Repetir um INSERT com a mesma PK falha sem baixar novamente o estoque. A trigger preenche `produto_nome`, `preco_unitario`, autoria do caixa e total: não envie esses valores como fonte da verdade. Caixa não pode editar/excluir itens depois da inserção. Admin pode corrigir itens pendentes; pedidos em produção/concluídos devem ser cancelados, não apagados. Cozinha avança apenas `pendente → preparando → pronto`; admin também entrega ou cancela.

## Estoque, auditoria e Realtime

- A baixa ocorre **AFTER INSERT** de item. Se faltar insumo, toda a inserção é revertida. Atualizações/exclusões de itens pendentes reconciliam o consumo; cancelamento devolve o snapshot original, mesmo que a ficha técnica tenha mudado. Produtos sem ficha não movimentam estoque. `modificadores` aceita somente chaves tipadas de ingredientes e ponto de preparo; rejeita texto livre e dados pessoais. Registra instruções e não altera automaticamente a receita.
- Total é a soma dos preços originais dos itens. Esta instalação não inclui desconto, taxa de entrega, status de pagamento, estorno nem confirmação Pix. Informar `metodo_pagamento = pix` **não comprova recebimento**. A passagem à cozinha não é condicionada a pagamento neste contrato reduzido; as integrações anteriores pertencem à outra sequência.
- Toda inserção, alteração e exclusão operacional é auditada; cancelamentos recebem a ação `PEDIDO_CANCELADO`. PIN/hash nunca entram nos snapshots. `audit_logs.updated_at` é inicializado e não pode ser modificado: a imutabilidade prevalece sobre a trigger de atualização de timestamps.
- A auditoria é imutável para DML inclusive do proprietário, mas alguém com acesso administrativo ao banco ainda pode alterar/desativar triggers por DDL. Não exponha credenciais `postgres`/`service_role` ao navegador.
- `orders` e `order_items` entram explicitamente em `supabase_realtime`, com lista de colunas sem valores financeiros, replica identity padrão e RLS. A lista é global: admin/caixa devem recarregar a visão financeira após eventos. No KDS assine ambas as tabelas e faça a primeira carga com os campos seguros; mudanças no Realtime não substituem essa consulta inicial.
- Não armazene telefone/endereço/documentos em `modificadores`: cozinha pode ler esse JSON. Este contrato não inclui cadastro de clientes; dados pessoais de delivery precisam de tabela separada e RLS própria.

## Validação

`bash scripts/test-sql-editor.sh` aplica este arquivo em PostgreSQL 17 descartável, com fixtures locais do Auth, e testa permissões por papel, isolamento de caixas, PIN, baixa/devolução/rollback, auditoria, timestamps, configuração de publicação e recusa de reinstalação. O mesmo comando aplica e testa o segundo arquivo separadamente, depois dos testes da base. O teste não se conecta ao projeto Supabase real nem valida a entrega WebSocket do serviço hospedado.
