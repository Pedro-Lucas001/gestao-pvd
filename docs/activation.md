# Ativar a operação real

Sequência para o frontend atual, contrato em inglês, migrações **001–018**. Publicar código não configura o banco nem os provedores. Homologar o projeto e os serviços da loja antes de divulgar pedidos reais.

## 1. O que precisa estar disponível

| Recurso | O que preparar | Quando é necessário |
|---|---|---|
| Supabase | Projeto ativo, banco compatível até a migração 018, Auth, Storage e funções publicadas | Toda a operação |
| Site | Projeto Vercel ou hospedagem compatível com Vite, URL HTTPS e variáveis públicas | Acesso de clientes e equipe |
| Administração | Conta no Auth promovida a administrador e navegadores cadastrados como terminais | Gestão e funcionários com PIN |
| Operação | Cardápio revisado, estoque inicial, custos e fichas técnicas | Vendas e indicadores confiáveis |
| Pix manual | Chave Pix e identificação do recebedor | Pix conferido pelo administrador |
| Mercado Pago | Conta/aplicação habilitada, credenciais de teste e produção e webhook | Pix/cartão online com confirmação pelo provedor |
| WhatsApp | Acesso à plataforma oficial da Meta ou solução compatível com a implementação, número habilitado e templates aprovados | Atendimento e avisos automáticos |
| OpenAI API | Chave de API válida, modelo acessível e faturamento/limites configurados | Assistente de IA |
| Agendamento | Chamada periódica ao integration-worker com segredo próprio | Processamento recorrente das filas do WhatsApp |

Não é necessário contratar todos os serviços para começar a testar o núcleo. É possível homologar cardápio, equipe, estoque, caixa e pedido em dinheiro antes de ativar pagamentos online, WhatsApp e IA.

## 2. Primeiro: descobrir a situação do banco

Abra o projeto correto no Supabase, entre no SQL Editor, crie uma consulta e execute somente este diagnóstico. Ele apenas consulta metadados:

```sql
select
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles' and column_name = 'name'
  ) as contrato_ingles,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles' and column_name = 'nome'
  ) as contrato_portugues,
  to_regprocedure('public.public_menu()') is not null as cardapio_015,
  to_regclass('public.online_orders') is not null as pedidos_016,
  to_regprocedure('public.online_ai_consent(text,text)') is not null as integracoes_017,
  to_regprocedure('public.admin_control_snapshot(date)') is not null as admin_018;
```

Interpretação:

- `contrato_ingles = true` e `contrato_portugues = false`: indício da estrutura esperada pelo frontend atual. Confira também o histórico e os resultados das migrações.
- `contrato_portugues = true`: não aplique automaticamente a sequência em inglês. É necessário avaliar a compatibilidade e eventual migração dos dados primeiro.
- Ambos falsos: pode ser um banco vazio ou outro esquema. Confirme o projeto antes de instalar qualquer coisa.
- Um indicador 015–018 falso aponta ausência daquele objeto, não identifica sozinho todos os arquivos que faltam. Um indicador verdadeiro também não comprova que uma migração inteira foi aplicada.

Os resultados não revelam credenciais. Não compartilhe senhas, tokens ou chaves privadas.

**Existem dois contratos de banco no repositório.** O frontend atual usa `supabase/migrations/`, com `profiles.name`, `active`, cargos `admin`, `cashier`, `kitchen`, preços em centavos e `recipe_items`. Os arquivos `supabase/sql_editor/planeta_lanches_completo.sql` e `planeta_lanches_ecossistema.sql` usam outro contrato, com nomes como `nome`, `ativo`, `caixa` e `cozinha`. Não misture esses scripts com as migrações do frontend atual. As funções `eco-*` pertencem à alternativa em português.

## 3. Aplicar somente as migrações necessárias

Antes de alterar um banco com dados reais, obtenha um backup e homologue em um projeto separado. Nunca execute `db reset`, os scripts de teste/bootstrap ou o SQL alternativo sobre a produção.

Para um projeto novo e vazio, execute [`supabase/activation/01_instalacao_nova.sql`](../supabase/activation/01_instalacao_nova.sql). O arquivo é gerado das migrações 001–018 e do seed, instala numa única transação e recusa tabelas públicas, estrutura operacional, usuários Auth ou buckets existentes. Não remover essa verificação. O recebimento de pedidos e a entrega começam pausados. Alternativamente, aplicar todos os arquivos de `supabase/migrations/`, de 001 até 018, em ordem crescente, e depois revisar/executar `supabase/seed.sql` uma única vez. Não usar os dois caminhos no mesmo banco.

Para um projeto existente: identificar a última migração realmente instalada e aplicar somente as posteriores, uma por vez. Por exemplo, se 001–014 estão completas:

1. `202611060015_public_menu.sql` — catálogo público servido pelo banco.
2. `202611070016_online_orders.sql` — pedidos online e alterações submetidas à cozinha.
3. `202611070017_online_integrations.sql` — pagamentos, consentimento, IA e notificações online.
4. `202611070018_admin_control.sql` — fotos, acessos da equipe e controle gerencial unificado.

No SQL Editor, abrir cada arquivo completo da versão atual, copiar e executar. Se houver erro, parar nessa etapa e guardar a mensagem; não executar os seguintes tentando compensar. Não remover comandos de transação para forçar a instalação.

Se o banco foi instalado manualmente, o histórico da CLI pode não refletir o que existe. Não usar `db push` nem marcar migrações como aplicadas sem reconciliar esse histórico. As opções da CLI variam entre versões; confirmar com `npx supabase --version` e a ajuda da versão instalada.

Alguns documentos antigos param em 014 ou 015. Para a versão analisada, o alvo é **018**. A migração 018 cria o bucket público específico `planeta-product-images`; não é preciso tornar outros buckets públicos.

## 4. Configurar o site

No computador, usar Node.js 22, como a validação do projeto. Na pasta correta, começar com `git status`. Havendo alterações locais, preservá-las antes de atualizar. Com a árvore limpa e a branch correta, atualizar pela main sem sobrescrever trabalho local.

```powershell
npm ci
npm run validate
```

Na Vercel: framework Vite, instalação `npm ci`, build `npm run build`, saída `dist`. Manter o `vercel.json` do repositório, que contém as rotas da aplicação e a política de conteúdo.

Configurar as variáveis do ambiente de produção:

```dotenv
VITE_SUPABASE_URL=https://SEU_PROJECT_REF.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=CHAVE_PUBLICA_DO_MESMO_PROJETO
VITE_APP_ENV=production
```

O código também aceita a variável legada `VITE_SUPABASE_ANON_KEY`. Usar a chave pública correspondente ao mesmo projeto da URL. Para desenvolvimento local, usar `.env.local`, sem versionar credenciais. Após mudar variáveis na hospedagem, gerar uma nova publicação.

Nunca colocar `service_role`, segredo de webhook, token do WhatsApp, chave OpenAI ou access token de pagamento em variáveis `VITE_*`: elas entram no código entregue ao navegador.

No Supabase Auth, configurar a URL real do site e os redirecionamentos necessários. Manter o cadastro público desabilitado; a equipe é criada pela administração. O `site_url` localhost em `supabase/config.toml` é de desenvolvimento e não comprova a configuração do projeto hospedado.

Se usar domínio próprio para a API Supabase ou outro host de imagens, revisar os hosts exatos no CSP de `vercel.json`. Não liberar todos os domínios para contornar um bloqueio.

## 5. Segredos do servidor e funções

Cadastrar os valores no painel seguro de segredos das Edge Functions do Supabase. O arquivo de exemplo existente não inclui todas as integrações novas. Substituir os marcadores abaixo; eles não são credenciais válidas.

### Base

```dotenv
APP_ALLOWED_ORIGINS=https://SEU_SITE.vercel.app
PUBLIC_SITE_URL=https://SEU_SITE.vercel.app
ONLINE_RATE_SALT=SEGREDO_ALEATORIO_EXCLUSIVO
INTEGRATION_WORKER_SECRET=OUTRO_SEGREDO_ALEATORIO_EXCLUSIVO
```

Em `APP_ALLOWED_ORIGINS`, usar origens exatas, sem caminho nem barra final; separar por vírgula se houver mais de uma. Incluir localhost apenas no ambiente de desenvolvimento/homologação necessário. Gerar os segredos com um gerenciador de senhas ou gerador criptográfico, sem reutilizar senha da loja.

O código das funções usa `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` do ambiente de servidor Supabase. Confirmar sua disponibilidade no ambiente adotado; não copiar a chave privilegiada para o site nem tentar substituir todas as chaves por uma única chave pública.

### Publicação seletiva

Publicar as funções a partir da raiz do repositório, com o `supabase/config.toml` atual. Publicar o site no GitHub/Vercel não publica essas funções automaticamente.

| Etapa | Funções |
|---|---|
| Acesso da equipe e diagnóstico | `fast-pass`, `staff-admin`, `integration-status` |
| Pix do PDV | `payment-intent`, `checkout-payment` |
| Pedidos e atendimento do site | `customer-api`, `customer-assistant`, `online-payment-webhook` |
| WhatsApp e processamento de filas | `whatsapp-webhook`, `whatsapp-send`, `integration-worker` |

Exemplo PowerShell para a implantação completa, depois de preparar o banco e os segredos:

```powershell
npx supabase login
npx supabase link --project-ref SEU_PROJECT_REF

$funcoes = @(
  'fast-pass', 'staff-admin', 'integration-status',
  'payment-intent', 'checkout-payment',
  'customer-api', 'customer-assistant', 'online-payment-webhook',
  'whatsapp-webhook', 'whatsapp-send', 'integration-worker'
)
foreach ($funcao in $funcoes) {
  npx supabase functions deploy $funcao --project-ref SEU_PROJECT_REF --use-api
  if ($LASTEXITCODE -ne 0) {
    throw "Falha ao publicar $funcao"
  }
}
```

Conferir o project ref antes da execução. O exemplo usa a publicação via API, disponível na CLI documentada. Não publicar todas as pastas indiscriminadamente, não adicionar `--no-verify-jwt` globalmente e não publicar `eco-*` para este contrato. O `provider-webhook` antigo não é o callback Mercado Pago da implementação online.

## 6. Criar o administrador e os funcionários

Após instalar o banco correto, criar a primeira conta em Supabase → Authentication → Users, com seu e-mail, nome e senha forte. Confirmar o e-mail conforme o fluxo escolhido. Copiar o UUID exato da conta.

No SQL Editor, substituir o UUID abaixo e promover somente essa conta:

```sql
begin;
select set_config(
  'app.audit_reason',
  'Ativação inicial autorizada do administrador',
  true
);
update public.profiles
set role = 'admin', active = true
where id = 'UUID_REAL_DA_CONTA';
commit;
```

Confirmar que a atualização afetou exatamente a conta escolhida. Depois entrar em `/login` com e-mail e senha. O administrador vai ao dashboard.

Em **Equipe e acessos**, cadastrar cada navegador físico como terminal, incluindo balcão e cozinha. O cadastro fica nesse navegador; outro aparelho ou perfil do navegador precisa de cadastro próprio.

Para novos funcionários, usar o formulário superior **Criar acesso da equipe**: nome, e-mail, senha inicial de pelo menos 12 caracteres, função e PIN individual de quatro dígitos. Para cozinha, escolher a praça correta. Não reutilizar o mesmo PIN entre funcionários ativos. Ambos os cargos chegam à área `/funcionario`, com ações permitidas pelo perfil verificado.

Após dez minutos sem atividade, o administrador confirma a senha da mesma conta para retomar a sessão. Uma senha recusada mantém a tela bloqueada. Funcionários retomam pelo PIN pessoal.

## 7. Preparar o funcionamento da loja

Antes de divulgar o link, manter o recebimento de pedidos online pausado nas configurações enquanto estiver homologando.

1. Revisar nomes, categorias, descrições, preços e disponibilidade. As categorias atuais incluem hambúrgueres, dogões, combos, porções, pastéis, coxinhas, bebidas e adicionais.
2. Cadastrar fotos pelo painel de produtos e verificar a imagem no cardápio público. A persistência real depende do Storage e da migração 018.
3. Cadastrar insumos, unidades coerentes (`g`, `ml`, `un`), custos e saldo inicial com justificativa.
4. Montar fichas técnicas, quantidades por produto e consumo dos adicionais/modificadores. Sem ficha e custo confiáveis, faturamento não comprova lucro; o painel pode sinalizar custo incompleto.
5. Calibrar tempo médio e capacidade das praças da cozinha.
6. Definir retirada, cobertura da entrega, taxa e recebimento em dinheiro/troco. Desabilitar entrega até esses dados estarem definidos; não presumir que o sistema consulta uma transportadora ou calcula distância automaticamente.
7. Abrir o turno de caixa antes de testar recebimento em dinheiro. Aceitar um pedido em dinheiro para preparo não equivale a registrar que o dinheiro já foi recebido.
8. Registrar despesas reais para os resultados diário, semanal e mensal terem significado. O dashboard é gerencial e depende desses lançamentos.

## 8. Ativar Pix e cartão

### Pix manual

Nos segredos das funções:

```dotenv
PAYMENT_MODE=manual_pix
PIX_KEY=SUA_CHAVE_PIX
PIX_MERCHANT_NAME=NOME_DO_RECEBEDOR
PIX_MERCHANT_CITY=SUA_CIDADE
```

Esse modo gera Pix para conferência manual. QR exibido e comprovante enviado não confirmam recebimento. O administrador deve conferir o crédito no extrato e registrar a referência real e a justificativa na tela correspondente. Devoluções bancárias também exigem execução e conferência no banco; um registro no painel não devolve dinheiro por si só.

### Mercado Pago para os pedidos online

Preparar uma aplicação/conta apta a receber os pagamentos e configurar:

```dotenv
MERCADOPAGO_ACCESS_TOKEN=TOKEN_DO_AMBIENTE_ESCOLHIDO
MERCADOPAGO_COLLECTOR_ID=ID_DO_RECEBEDOR_CORRETO
MERCADOPAGO_WEBHOOK_SECRET=SEGREDO_DA_ASSINATURA_DO_WEBHOOK
MERCADOPAGO_LIVE_MODE=false
```

Começar com credenciais e recursos de teste correspondentes, respeitando as exigências de teste do provedor. Configurar eventos **Pagamentos/Payments** para a integração baseada em Preferences/Payments usada no código. URL de notificação:

```text
https://SEU_PROJECT_REF.supabase.co/functions/v1/online-payment-webhook
```

O código valida assinatura e consulta os dados do pagamento. Não substituir esse endpoint por `provider-webhook`. Depois de homologar, trocar para as credenciais de produção e `MERCADOPAGO_LIVE_MODE=true` de modo consistente.

O provedor online configurado tem prioridade sobre o Pix manual nos pedidos do site. Cartão online via checkout não é integração com maquininha: **TEF do PDV não está implementado**. Não anunciar essa função como ativa. Conferir taxas e condições diretamente na conta do provedor antes de habilitar recebimento real.

## 9. WhatsApp e avisos de alteração

Preparar WhatsApp Business Platform/Cloud API, número habilitado, token válido, app e modelos aprovados. Ter apenas o aplicativo WhatsApp Business instalado não fornece as credenciais da API. Antes de alterar o número atual da loja, conferir com a Meta/provedor a elegibilidade e as opções de coexistência/migração.

Configurar nos segredos:

```dotenv
WHATSAPP_ACCESS_TOKEN=TOKEN_DO_SERVIDOR
WHATSAPP_PHONE_NUMBER_ID=ID_DO_NUMERO
WHATSAPP_APP_SECRET=SEGREDO_DO_APP_META
WHATSAPP_VERIFY_TOKEN=SEGREDO_ALEATORIO_DE_VERIFICACAO
WHATSAPP_GRAPH_VERSION=v23.0
WHATSAPP_MENU_URL=https://SEU_SITE.vercel.app/cardapio
WHATSAPP_TEMPLATE_LANGUAGE=pt_BR
WHATSAPP_STATUS_TEMPLATE=NOME_TEMPLATE_STATUS_PDV
WHATSAPP_ONLINE_STATUS_TEMPLATE=NOME_TEMPLATE_STATUS_ONLINE
WHATSAPP_ONLINE_PAYMENT_TEMPLATE=NOME_TEMPLATE_PIX_COMPLEMENTAR
```

`v23.0` é o padrão do código analisado; confirmar a versão suportada pelo app antes de escolher outra. Os templates devem corresponder aos parâmetros enviados:

| Template | Parâmetros no corpo, em ordem |
|---|---|
| Status do PDV | número do pedido; status |
| Status online | número do pedido; status |
| Pagamento complementar online | número do pedido; valor formatado; Pix copia e cola |

No painel Meta, apontar o webhook para:

```text
https://SEU_PROJECT_REF.supabase.co/functions/v1/whatsapp-webhook
```

Usar o mesmo verify token do segredo e assinar os eventos `messages`. Testar a verificação e uma mensagem recebida. Fora da janela de atendimento aplicável, a implementação usa templates aprovados; sem eles, notificações podem ficar pendentes. Respeitar o consentimento do cliente para avisos.

A alteração solicitada pelo cliente depende de decisão da cozinha. Quando aceita, uma diferença positiva pode gerar pagamento complementar e notificação com Pix. Isso exige provedor/Pix configurado, consentimento, templates quando necessários e processamento da fila. Rejeição, pagamento pendente e recebimento têm estados distintos. Não prometer reembolso bancário automático para redução de valor.

## 10. Agendar o processamento das mensagens

O worker recebe `POST` em:

```text
https://SEU_PROJECT_REF.supabase.co/functions/v1/integration-worker
```

Cabeçalho: `X-Worker-Secret` com o mesmo valor de `INTEGRATION_WORKER_SECRET`. Corpo: `{}`. Agendar a cada minuto. Não colocar esse segredo no frontend nem em URL pública.

Uma opção é Supabase Cron + pg_net + Vault. Primeiro habilitar Cron/pg_net no projeto e cadastrar, pelo painel seguro do Vault:

- `planeta_project_url`: origem HTTPS do seu projeto Supabase, sem barra final.
- `planeta_worker_secret`: mesmo valor usado em `INTEGRATION_WORKER_SECRET`.

Depois criar uma única tarefa, conferindo que ainda não há outra equivalente:

```sql
select cron.schedule(
  'planeta-integracoes-a-cada-minuto',
  '* * * * *',
  $job$
    select net.http_post(
      url := (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'planeta_project_url'
      ) || '/functions/v1/integration-worker',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'X-Worker-Secret', (
          select decrypted_secret from vault.decrypted_secrets
          where name = 'planeta_worker_secret'
        )
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
  $job$
);
```

Validar tanto a execução do Cron quanto a resposta HTTP e os logs da função. Uma tarefa SQL bem-sucedida só comprova que a chamada foi enfileirada, não que o WhatsApp entregou a mensagem. O disparo oportunista feito por alguns endpoints não substitui o agendamento recorrente.

## 11. Ativar a IA

Na conta da API OpenAI, preparar uma chave privada, acesso ao modelo e faturamento/limites adequados. A assinatura do ChatGPT, sozinha, não configura o servidor do sistema.

```dotenv
OPENAI_API_KEY=CHAVE_PRIVADA_DA_API
OPENAI_SALES_MODEL=gpt-4.1-mini
AI_CUSTOMER_EXPORT_ENABLED=true
AI_DAILY_REQUEST_LIMIT=20
```

O modelo indicado é o padrão atual do código. O limite de 20 requisições/dia é uma sugestão inicial conservadora de configuração, ajustável após os testes. Também definir limites/alertas na conta do provedor.

No site, testar o consentimento antes de usar o assistente. No WhatsApp, o fluxo atual reconhece `AUTORIZO IA`, `SEM IA` e `HUMANO`. Divulgar contato de atendimento humano e informações de privacidade adequadas à operação antes de receber clientes reais.

O assistente trabalha com catálogo e sugere itens; a confirmação do pedido ocorre pelo site. O estado real do banco e dos provedores continua sendo a fonte de verdade. Não há checkout completo exclusivamente por conversa no WhatsApp nem confirmação de pagamento pela interpretação da IA. Áudios e imagens não constituem atendimento multimodal implementado nesse fluxo.

## Validação e publicação

```sh
npm ci
npm run validate
npm run activation:check
npm run test:db
bash scripts/test-activation.sh
```

Os testes SQL exigem Docker e usam exclusivamente bancos descartáveis. O instalador é testado com instalação inicial, recusa de repetição e as suítes operacionais existentes. As fixtures nunca são enviadas para o Supabase da loja.

O CI fixa Deno 2.9.8 e define `DENO_NO_PACKAGE_JSON=1` nos passos das funções. Assim, as funções usam sua configuração em `supabase/functions/deno.json` e não instalam o Vite/PWA/Rollup do frontend. A proteção de idade mínima das dependências continua ativa. As importações do SDK no backend estão fixadas em 2.99.0.

Para publicar seletivamente no PowerShell, após login da CLI e configuração segura dos segredos:

```powershell
npx supabase login
./scripts/deploy-functions.ps1 -ProjectRef SEU_PROJECT_REF -Group all
```

Grupos: `core` para acesso/Pix do PDV; `online` inclui core e pedidos do site; `whatsapp` inclui core e WhatsApp; `all` reúne os três. O script não aplica SQL e não cadastra segredos. Respeita os `verify_jwt` do config.toml e interrompe a sequência se uma publicação falhar.

O painel **Integrações** mostra a presença das configurações de Pix, Mercado Pago, IA, WhatsApp e templates. Ele não faz cobrança, não verifica aprovação de template e não comprova execução do Cron nem entrega ao cliente.

Antes de abrir: testar cardápio anônimo, foto real, PIN/isolamento de cargos, bloqueio e senha do admin, caixa, estoque por ficha, retry sem duplicação, modalidades de pagamento escolhidas, alteração pela cozinha e avisos consentidos. Confira os resultados financeiro e de custos usando os lançamentos reais.
