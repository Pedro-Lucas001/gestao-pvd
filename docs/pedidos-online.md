# Cardápio, pedidos online e atendimento

O PR adiciona o fluxo novo em `/cardapio` e `/pedido`. Os links antigos `/pedido?token=...` continuam na tela de autoatendimento anterior. A nova compra não usa a sessão administrativa. Produtos e preços vêm do catálogo ativo; o servidor ignora preços enviados pelo navegador ou pela IA.

## Experiência do cliente

- Seções de hambúrgueres, dogs na chapa, porções, pastéis, mini coxinhas, bebidas e adicionais; busca e filtros combinados. Categorias novas também aparecem.
- Carrinho por aba, quantidades, observações e personalizações permitidas. Itens adicionais são linhas identificadas no pedido; use as observações para indicar em qual lanche devem entrar.
- Retirada ou entrega, nome, WhatsApp, e-mail e endereço quando necessário. A entrega tem uma taxa única configurável; não há cálculo por distância nem validação automática de CEP/raio. Antes de habilitar entrega, a loja precisa definir e comunicar sua área de atendimento.
- Pix, cartão em checkout hospedado no Mercado Pago e dinheiro quando habilitado. E-mail também é solicitado no dinheiro para permitir Pix de uma eventual adição posterior. Para troco, o valor informado deve cobrir o total.
- A tentativa de envio é preservada na mesma aba em caso de rede incerta. Retome a mesma tentativa; não abra outra compra para resolver um pagamento incerto. Dados de contato ficam temporariamente nessa tentativa e são removidos depois da confirmação.
- Link privado de acompanhamento no fragmento da URL, com token aleatório de 256 bits e somente hash no banco. Quem possui o link pode ver itens e solicitar alterações; não o publique. O acompanhamento não retorna endereço, telefone nem e-mail.

## Cozinha, caixa e alterações

`/pedidos-online` é permitido para caixa e admin; a cozinha encontra a fila online acima da fila real do PDV em `/cozinha`. Cada cozinha vê apenas seu setor, sem valores ou contatos. O caixa precisa abrir turno e assumir o pedido para acessar o contato. Admin pode administrar todas as operações.

Pedidos eletrônicos entram no preparo após confirmação confiável. Pedidos em dinheiro aguardam o aceite da loja; esse aceite libera o preparo como conta a receber, sem declarar pagamento. O caixa registra dinheiro efetivamente recebido e troco. O valor líquido recebido entra no resumo do turno, e o turno não fecha com pedidos online atribuídos ainda a receber. Indicadores online ficam na nova página; os relatórios/DRE antigos do PDV continuam separados.

O cliente pode propor uma revisão completa enquanto o pedido estiver na fila ou em preparo. A cozinha precisa decidir a solicitação antes de avançar o ticket. Todos os setores do pedido antigo e do proposto precisam aprovar; uma recusa conserva o pedido original. Admin pode aprovar todos os setores. As telas exibem a proposta completa e a instrução da revisão: a equipe deve preservar o que já foi produzido e conferir as diferenças, sem refazer automaticamente itens prontos.

Quando uma compra já paga ganha valor, a revisão aprovada aguarda um Pix complementar. Só o recebimento libera a revisão. Setores com itens idênticos preservam seu estado; insumos adicionais são baixados atomicamente, e remoções não devolvem automaticamente insumos preparados ao estoque. Reduções pagas geram saldo a devolver: admin faz a devolução pelo banco e registra a referência real. O botão de registro não transfere dinheiro. Cancelamentos integrais, disputa/chargeback e exceções do provedor precisam do atendimento da loja; não há estorno automático no provedor neste PR.

## Ativação em homologação

1. Aplique as migrações anteriores, incluindo `202611060015_public_menu.sql` (confira o nome exato no diretório), e depois `202611070016_online_orders.sql` e `202611070017_online_integrations.sql`, nessa ordem. Faça backup e valide primeiro em um projeto de homologação. Os arquivos consolidados antigos de SQL Editor não incluem as migrações 015–017.
2. Publique `customer-api`, `customer-assistant`, `online-payment-webhook`, `whatsapp-webhook` e `integration-worker`. Mantenha `verify_jwt=false` dessas funções como no `supabase/config.toml`; as APIs públicas têm CORS, limites e capacidades próprias, e webhooks/worker têm assinatura ou segredo. Não abra as tabelas online a visitantes.
3. Configure no frontend somente a URL e a chave pública do Supabase. Segredos abaixo pertencem **às Edge Functions**, nunca às variáveis `VITE_*`.
4. Em **Pedidos online → Configurar**, confira a pausa de pedidos, dinheiro, taxa, habilitação de entrega e WhatsApp da loja com país/DDD. Entrega começa desabilitada. Cadastre fichas técnicas e regras de modificadores do catálogo para a baixa de estoque refletir a operação.
5. Homologue os cenários da lista final antes de abrir pedidos ao público.

### Segredos das funções

| Variável | Finalidade |
| --- | --- |
| `APP_ALLOWED_ORIGINS` | Origens HTTPS exatas do site, separadas por vírgula; já usada pelas funções existentes |
| `PUBLIC_SITE_URL` | Origem HTTPS pública do site, sem query/fragmento |
| `ONLINE_RATE_SALT` | Segredo aleatório para hash dos limites por IP; não é uma chave pública |
| `MERCADOPAGO_ACCESS_TOKEN` | Acesso privado da conta recebedora |
| `MERCADOPAGO_COLLECTOR_ID` | ID numérico dessa mesma conta |
| `MERCADOPAGO_WEBHOOK_SECRET` | Segredo de assinatura do webhook configurado no painel Mercado Pago |
| `MERCADOPAGO_LIVE_MODE` | `false` em teste; só mudar para `true` depois da homologação |
| `PAYMENT_MODE`, `PIX_KEY`, `PIX_MERCHANT_NAME`, `PIX_MERCHANT_CITY` | Alternativa `manual_pix` quando Mercado Pago não estiver configurado; exige conferência do crédito pelo admin |
| `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_APP_SECRET`, `WHATSAPP_VERIFY_TOKEN` | API oficial da Meta e validação de webhook |
| `WHATSAPP_GRAPH_VERSION` | Versão habilitada no aplicativo Meta, padrão existente `v23.0` |
| `WHATSAPP_MENU_URL` | URL pública do cardápio para a resposta do WhatsApp |
| `WHATSAPP_ONLINE_STATUS_TEMPLATE` | Modelo aprovado com parâmetros: número do pedido, descrição do evento |
| `WHATSAPP_ONLINE_PAYMENT_TEMPLATE` | Modelo aprovado com parâmetros: número do pedido, valor, código Pix copia e cola |
| `WHATSAPP_TEMPLATE_LANGUAGE` | Idioma aprovado, padrão `pt_BR` |
| `INTEGRATION_WORKER_SECRET` | Segredo aleatório do worker/agendador, já utilizado na integração anterior |
| `OPENAI_API_KEY` | Chave privada para atendimento com IA |
| `OPENAI_SALES_MODEL` | Modelo compatível com Responses e Structured Outputs, padrão `gpt-4.1-mini` |
| `AI_DAILY_REQUEST_LIMIT` | Teto compartilhado de chamadas de IA por janela de 24 horas, padrão 200 e máximo 1000 |

Supabase já fornece `SUPABASE_URL` e a chave de serviço ao ambiente das funções. Não copie a chave de serviço para o site, o GitHub ou mensagens de atendimento.

### Mercado Pago e Pix

Configure a URL de notificação para `https://SEU-PROJETO.supabase.co/functions/v1/online-payment-webhook`. O servidor verifica HMAC e consulta novamente o pagamento autenticado, conferindo recebedor, modo teste/produção, BRL, referência e valor. Redirecionamento, comprovante e mensagens do cliente não confirmam pagamento. Cartões são preenchidos apenas no checkout do Mercado Pago; o site não armazena PAN/CVV. A preferência exclui boleto/transferência para manter cartão no checkout hospedado.

No Pix manual, admin confirma o valor pelo extrato usando a referência real do banco. A referência não pode ser reutilizada em compras do balcão e online. Não simule pagamento para liberar preparo em produção.

Uma criação de cartão cujo resultado se perdeu tenta localizar a preferência pela referência, sem recriá-la cegamente. Se o provedor não der resposta inequívoca, a equipe precisa conciliar. Pagamentos expirados, rejeitados, cobranças duplicadas no provedor ou estornos devem ser conferidos no painel da conta recebedora. Não se deve criar outra compra para contornar um estado incerto.

### WhatsApp e agendador

Configure o webhook oficial existente `whatsapp-webhook` na Meta, assine mensagens e confirme a assinatura do aplicativo. A chegada de mensagem dispara uma tentativa em segundo plano do worker. Configure também o agendamento durável do `integration-worker` **a cada minuto**, com POST e header `X-Worker-Secret`. Use o scheduler já documentado em `docs/deploy.md` ou Supabase Cron/Vault; mantenha o segredo no Vault/ambiente do agendador. Exemplo lógico (o agendador deve resolver o segredo em tempo de execução):

```text
POST https://SEU-PROJETO.supabase.co/functions/v1/integration-worker
X-Worker-Secret: [segredo privado do agendador]
```

As notificações entram em uma fila com tentativas, lease e backoff, até oito tentativas. Fora da janela de conversa conservadora de 23 horas, o envio depende dos modelos aprovados. Para alterações pagas aceitas com saldo pendente, o worker cria/reutiliza a cobrança complementar e envia o Pix. Falha ou falta de modelo não marca a mensagem como entregue. Não há garantia de entrega exatamente uma vez quando a Meta recebe e a resposta de rede se perde; o saldo/pagamento continua protegido por idempotência. Acompanhe falhas da fila no Supabase e o estado no painel Meta. O acompanhamento no site permanece disponível sem consentimento para WhatsApp.

### Atendimento com IA

O assistente usa o mesmo catálogo do site. Interpreta escolhas e devolve uma proposta de carrinho com IDs, quantidades e modificadores validados no servidor. No site o cliente aplica a sugestão; no WhatsApp recebe um link para revisar e confirmar a compra no site. A finalização não ocorre exclusivamente na conversa. A IA não altera pedidos, aceita alterações, decide devoluções ou confirma pagamentos. Só as funções de negócio executam essas operações.

As respostas finais são montadas pelo servidor, com preço canônico. Não há respostas livres do modelo afirmando que uma compra foi paga. Somente catálogo e mensagens recentes do atendimento são enviados à OpenAI; números de telefone e e-mails são removidos automaticamente do texto, mas isso não substitui uma política de privacidade nem remove todos os dados pessoais possíveis. Não envie documentos, endereços, senhas ou dados de cartão ao chat. `store=false` é usado na Responses API; configure retenção/contrato conforme a conta da loja. Sem chave, em erro, em alergias/reclamações ou ao pedir HUMANO, há encaminhamento à equipe. O atendimento humano atribuído pausa a automação no WhatsApp, e o pedido de HUMANO a pausa por 24 horas. Admin pode retomar pela função `online_resume_automation` com justificativa.

## Verificações

`npm run validate`: lint, testes JavaScript e build. `npm run test:db`: PostgreSQL descartável, migrações e suítes de RLS/negócio, incluindo `supabase/tests/online.sql`. Deno check e testes puros cobrem assinatura do provedor, URLs permitidas, valores e saídas de IA.

Homologação externa obrigatória antes de ativar: Pix aprovado e callback repetido; cartão aprovado/recusado/retorno interrompido; dinheiro com e sem troco; mudança de taxa entre compra e revisão; aprovação em dois setores e recusa; adição paga antes do preparo revisado; saldo a devolver; bloqueio de turno; WhatsApp dentro/fora da janela com modelos aprovados, consentimento recusado, encaminhamento humano e provedor indisponível. Estes testes não fazem cobranças ou enviam mensagens reais na suíte automatizada.
