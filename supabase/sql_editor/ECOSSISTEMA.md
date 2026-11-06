# Partes 5 e 6 — vendas assistidas, integrações e privacidade

Este módulo estende **somente** `planeta_lanches_completo.sql`, com o contrato em português. Não o aplique à sequência de `supabase/migrations/` em inglês. O frontend operacional existente usa essa outra sequência e precisa de adaptação antes de consumir o novo contrato. Os scripts não renomeiam nem sobrescrevem dados existentes, e não foram aplicados a nenhum projeto hospedado.

## O que está pronto no código

- **Venda pelo WhatsApp:** webhook da API oficial Meta verifica HMAC do corpo original e número de destino, deduplica mensagens e grava fila privada. O worker lê o cardápio atual e conversa com o modelo OpenAI por ferramenta estruturada. A ferramenta prepara um resumo com preços recalculados no banco; somente a mensagem literal **CONFIRMAR** cria a venda, uma única vez. O estoque é reservado na inclusão dos itens. A cozinha recebe os mesmos `orders`/`order_items`, após confirmação de pagamento.
- **Entrega:** endereço fica no schema privado, vinculado ao cliente. O cliente informa os produtos e endereço, mas a equipe ainda precisa confirmar área, disponibilidade de entrega e eventual taxa. Esta versão não calcula frete nem soma taxa ao total; o resumo identifica o total dos produtos. A API logística exige um canal autorizado atribuído ao pedido. Não confirme a venda com valor final diferente sem implementar a taxa no cálculo do servidor.
- **Fidelidade:** ledger `loyalty_points` registra uma vez por pedido entregue e pago; padrão de **1 ponto por R$ 1**, arredondado para baixo. O admin pode alterar `loyalty_settings.pontos_por_real` para vendas futuras. Estorno do pagamento gera lançamento negativo sem apagar o crédito original. Pontos não representam cashback em dinheiro; resgate de pontos não faz parte deste módulo.
- **Retenção:** `clientes_inativos_15_dias` seleciona compras finalizadas/pagas há mais de 15 dias, com opt-in e sem pedido de exclusão. `marketing_campaigns` → `iniciar_campanha` → `marketing_deliveries` usa template aprovado da Meta, sem parâmetros pessoais. Compra não autoriza marketing. **QUERO RECEBER PROMOÇÕES** autoriza; **SAIR/PARAR** revoga imediatamente e cancela a fila. Rechecagem antes de enviar, máximo 30 tentativas/minuto no total, intervalo de 7 dias entre campanhas por cliente e quatro tentativas limitadas. Mensagem já em trânsito pode chegar após uma revogação.
- **Ecossistema:** API de ponte assinada aceita venda, eventos de logística e consulta/ack de eventos de conversão. Cada origem possui chave e escopos próprios, SKUs mapeados e registros idempotentes. Os adaptadores genéricos não são uma integração nativa/homologada com iFood, transportadoras ou plataformas de anúncios. Credenciamento e tradução dos webhooks reais de cada fornecedor continuam necessários; o gateway não finge autenticação dos fornecedores.
- **Privacidade:** contatos/conversas/tokens ficam em `planeta_private`, sem SELECT nem mesmo com a chave pública de um admin. Atendimento legítimo usa RPC por pedido ativo atribuído ou por atendimento humano assumido, com limite de 30 consultas/minuto por funcionário e trilha sem PII. Cozinha não vê contatos, histórico financeiro ou fila de marketing. Nenhum endpoint exporta a base de contatos para o navegador.
- **Direitos do titular:** mensagem **PRIVACIDADE** produz link aleatório de 256 bits, hash no banco, validade de 15 minutos e entrega pela conversa autenticada pela Meta. O portal permite baixar JSON apenas do titular, revogar/autorizar medição de anúncios e clicar em **Esquecer meus dados**. Pedidos em andamento adiam a execução; ao encerrá-los, um trigger remove contatos, endereços, conversas, rascunhos, tokens e cancela campanhas. A resposta de exclusão é idempotente durante 24 horas. Auditoria e compras mínimas permanecem pseudonimizadas para conciliação; não se promete apagar contabilidade nem os dados que Meta/OpenAI conservam segundo seus contratos.

A segregação bloqueia a exportação em massa por cozinha, anônimos e funcionários sem atribuição. Um usuário autorizado ainda pode copiar os dados que legitimamente recebe; RLS não impede capturas de tela nem elimina o poder administrativo do proprietário do banco. Não exponha `service_role`/credenciais SQL e não habilite o schema privado na API.

## Ordem de instalação

1. Execute os dois arquivos SQL em ordem no SQL Editor como `postgres`.
2. Crie e ative o primeiro admin e configure um PIN próprio conforme README. Crie no Auth uma **conta interna dedicada**, sem divulgar suas credenciais, ative seu perfil como caixa e configure `integration_sources.user_id`. Os canais começam inativos.
3. Cadastre categorias, produtos, fichas e estoque reais. Configure fontes/escopos e traduções de SKU para cada ponte. A chave pública/URL do frontend não fazem esse cadastro nem transformam uma conexão em integração ativa.
4. Configure os segredos server-side em `supabase/.env.example`; nunca nas variáveis `VITE_*`. Meta exige API oficial, app, webhook e token de acesso; o aplicativo WhatsApp Business sozinho não fornece esse acesso. OpenAI exige uma chave de projeto e tratamento/transparência adequados ao conteúdo encaminhado. Nenhum credenciamento foi feito neste trabalho.
5. Faça deploy **somente** das funções alternativas necessárias:

   ```sh
   supabase functions deploy eco-whatsapp-webhook
   supabase functions deploy eco-worker
   supabase functions deploy eco-gateway
   supabase functions deploy eco-lgpd
   ```

6. Configure na Meta o webhook `/functions/v1/eco-whatsapp-webhook` e o verify token escolhido. Não direcione simultaneamente o mesmo evento ao webhook em inglês: são instalações alternativas.
7. Hospede a pasta `portal/` como arquivos estáticos em HTTPS, substitua `data-api-url` em `index.html` pela URL real do endpoint `eco-lgpd`, configure `ECO_PRIVACY_PORTAL_URL` e adicione a origem a `APP_ALLOWED_ORIGINS`. Em domínio Supabase customizado, ajuste também o `connect-src` do CSP do portal. Sirva com `Cache-Control: no-store`, `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff` e CSP HTTP `frame-ancestors 'none'`. O token fica no fragmento, removido imediatamente, sem cookies/localStorage/analytics.
8. Agende POST em `eco-worker` com header secreto `X-Worker-Secret`, no mínimo a cada minuto. O webhook também solicita um processamento em background ao receber mensagens. Uma execução atende um job de conversa e um de campanha, com locks por cliente; várias execuções podem atender clientes diferentes. O agendador deve guardar o segredo no próprio cofre; ele não é embutido no SQL nem no frontend.

Exemplo de ativação do canal (substitua UUID pela conta dedicada):

```sql
update public.integration_sources
set ativo = true, user_id = 'UUID-DA-CONTA-INTERNA'
where id = 'whatsapp';
```

Nenhum canal é ativado automaticamente, nenhum deploy/pagamento/disparo foi realizado. Sem credenciais Meta, o worker recusa o processamento; sem OpenAI, encaminha o atendimento à fila humana. Os modelos, custos, contratos de tratamento e templates aprovados devem ser configurados pela operação.

## Contrato do gateway

Chaves diferentes por canal em `ECO_GATEWAY_KEYS` (JSON server-side). Assinatura header `X-Signature: sha256=<hex HMAC-SHA256>` sobre os bytes exatos:

```text
MÉTODO\nCAMINHO_E_QUERY\nORIGEM\nTIMESTAMP_UNIX_SEGUNDOS\nCORPO_ORIGINAL
```

Exemplo de caminho: `/functions/v1/eco-gateway/orders`. Use a mesma capitalização e o mesmo caminho recebido no endpoint; não reserialize o JSON depois de assinar. Headers `X-Integration-Source` e `X-Timestamp` são obrigatórios, com tolerância de cinco minutos. Repetições legítimas usam os mesmos IDs; conteúdo divergente com os mesmos IDs é rejeitado. O transporte exige HTTPS.

| Rota | Escopo | Contrato |
| --- | --- | --- |
| POST `/eco-gateway/orders` | `orders` | `event_id`, `external_order_id`, `order: { tipo: "balcao", metodo_pagamento, itens: [{sku,quantidade,modificadores}] }` |
| POST `/eco-gateway/fulfillment` | `fulfillment` | `event_id`, `order_id`, `status: "despachado" ou "entregue"`; exige `orders.logistics_source` atribuído à origem |
| GET `/eco-gateway/events` | `ads` | Até 50 eventos pendentes, sem telefone/endereço; só gera conversão se o cliente autorizou anúncios separadamente |
| POST `/eco-gateway/ack` | `ads` | `{ id }`, após consumir evento com idempotência no destino |

A ponte genérica de vendas aceita retirada no balcão. Delivery de marketplace exige adaptador próprio que grave o contato/endereço com a finalidade e autorização corretas; inserir dados pessoais no payload genérico é rejeitado. Valores são sempre locais; campos `pago`, totais arbitrários ou payload com PII não são aceitos. O formato original de assinatura de iFood/Meta/etc. deve ser validado pelo adaptador específico antes de assinar o envelope interno.

**Pix Nubank PF continua manual:** admin usa `confirmar_pagamento(order_id, referencia_real_do_extrato)` depois de verificar o recebimento no banco. Caixa pode confirmar somente dinheiro do próprio pedido. Apenas escolher Pix ou apresentar um comprovante não confirma crédito. Não há estorno bancário automático, TEF ou impressão implementados por este módulo SQL. Adapters de PSP/TEF/impressão continuam sendo serviços próprios.

## APIs de governança e atendimento

- POST `/eco-lgpd`: `{ token, acao: "acesso" | "anonimizacao" | "consentir_anuncios" | "revogar_anuncios" }`. Capacidade pessoal expira em 15 minutos; nenhuma busca por telefone, UUID de cliente ou JWT de funcionário substitui essa prova. O endpoint não exige conta do cliente no Auth. CORS limita as origens do portal; autenticação real depende do token, não do CORS.
- `assumir_pedido(order_id)` e `contato_do_pedido(order_id)`: admin ou caixa autorizado, com acesso por pedido ativo; o contato some ao encerrar o pedido.
- **HUMANO** cria `ai_handoffs`; `assumir_atendimento(id)` atribui o atendimento e `detalhes_atendimento(id)` retorna só aquele contato/conversa à pessoa responsável. Admin conclui pelo campo `status`. Esta fila e as campanhas ainda precisam de telas no frontend que consome o novo contrato. O painel anterior em inglês não as consulta automaticamente.
- Integração de respostas humanas pela API, transcrição de áudio, validação de frete/área e resgate de pontos são extensões posteriores. O webhook atual aceita somente texto.

## Limites e retenção

`eco_cleanup`, executada pelo worker, elimina conversas/jobs antigos após sete dias, tokens expirados, recibos de replay após 90 dias e contatos sem compras após 90 dias sem interação. A limpeza depende de agendamento ativo. Os prazos de documentos financeiros/auditoria devem refletir as obrigações aplicáveis ao estabelecimento; este módulo preserva esses registros e não afirma certificação/conformidade jurídica automática. A anonimização mantém identificadores aleatórios nos registros financeiros, sem conservar contato/endereço no banco da aplicação; backups e sistemas externos precisam de política própria de retenção.

Os envios Meta são **pelo menos uma vez**: o banco evita criar a mesma venda duas vezes, mas uma falha depois da entrega pela Meta e antes do ack local pode repetir uma mensagem. Leases, limites de tentativas e deduplicação reduzem o risco; não existe transação distribuída com a Meta. Não use texto de IA como comprovante financeiro. Sugestões da IA passam por validação de preço/produto/modificadores, confirmação explícita e validação final de estoque; isso não garante que toda resposta em linguagem natural esteja livre de erro.

## Verificação

`bash scripts/test-sql-editor.sh` executa os dois scripts em PostgreSQL 17 descartável e testa RLS, snapshots, pagamentos, pontos, consentimento/opt-out, isolamento de contato, relatório do titular, exclusão adiada/conclusão e idempotência de integrações. Os testes Deno validam HMAC, mudança de origem/rota/corpo, expiração, comandos e dados de modificadores. Nenhum teste envia mensagens reais, chama OpenAI/marketplaces ou comprova entrega WebSocket do Realtime hospedado.
