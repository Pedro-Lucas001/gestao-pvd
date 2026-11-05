# Ativar a operação real

Nenhuma credencial da loja foi fornecida e nenhum projeto Supabase foi criado neste chat. Os testes locais não ativam serviços hospedados.

## 1. Supabase staging

Crie um projeto de staging e outro de produção. Desative signup público e aplique todas as migrations `202611050001` a `202611050014` na ordem. Importe o seed uma vez (não sobrescreve produtos existentes). As tabelas privadas e tabelas de auditoria não devem ser adicionadas ao Realtime; apenas tickets sanitizados e agregados de carga por praça são publicados.

Crie sua conta no Auth (senha forte, e-mail conferido) e promova somente o UUID correto pelo SQL Editor:

```sql
begin;
select set_config('app.audit_reason','Ativação inicial autorizada do administrador',true);
update public.profiles set role='admin',active=true where id='UUID_REAL_DO_ADMIN';
commit;
```

Configure URL e chave **publishable/anon pública** do staging em `.env.local` e inicie `npm run dev`. O primeiro admin entra com e-mail/senha. Em **Equipe e acessos** cadastre este navegador como terminal, configure seu próprio PIN e crie os funcionários com funções e setores adequados. Cada estação (balcão/cozinha) precisa de cadastro no seu navegador. O token do terminal não é transferido automaticamente para outro dispositivo.

Cadastre custos, quantidades, fichas técnicas e regras de modificadores reais. Revise sobreposições de exclusões: o consumo final nunca fica negativo. As margens exibem custo da receita padrão atual; não são fechamento contábil histórico. Defina e comunique a área/condições de entrega e todos os produtos/adicionais cobrados antes de compartilhar o link público; não foram inventadas taxas.

## 2. Pix Nubank físico: fluxo manual explícito

A informação disponível é conta física e chave Pix no app. A chave não oferece um canal de confirmação automática ao sistema. Configure **nos segredos das funções Supabase**, não no frontend:

```text
PAYMENT_MODE=manual_pix
PIX_KEY=<sua chave, informada somente no painel seguro>
PIX_MERCHANT_NAME=<identificação do estabelecimento>
PIX_MERCHANT_CITY=CARPINA
APP_ALLOWED_ORIGINS=<origens HTTPS exatas do frontend, separadas por vírgula>
```

Publique `payment-intent`, `checkout-payment` e `integration-status`. As funções usam as credenciais Supabase server-side disponibilizadas pelo projeto. O QR é BR Code estático com valor fixo e CRC16; **não** é Pix Cob dinâmico e não possui expiração bancária automática. Nenhuma aprovação é inferida ao exibir um QR ou receber um comprovante.

Em **Pagamentos e estornos**, o admin confere o valor creditado no extrato, informa a referência real do banco e a justificativa. A mesma referência normalizada não pode pagar dois pedidos. Após confirmação ocorre a liberação atômica para cozinha e a baixa de insumos. Faça a devolução Pix no aplicativo bancário e só depois registre a referência de devolução. Estorno em dinheiro exige caixa aberto do administrador, saldo suficiente e confirmação de devolução física. Pedido/refund não repõe alimentos automaticamente.

Para encerrar um Pix estático abandonado, o administrador confere a ausência de crédito e registra o motivo. O QR pode continuar tecnicamente pagável no banco: crédito tardio é registrado sem reabrir o pedido na cozinha, aparece como valor a devolver e exige conciliação/estorno.

Para **Pix/estorno automático**, contrate ou forneça acesso a um PSP/API oficial e homologue um adaptador. Não existe integração de saldo bancário configurada para essa conta física. **TEF** continua bloqueado até informar marca/modelo, serviço contratado e ambiente de homologação; aprovações não são simuladas.

## 3. WhatsApp

Hoje a loja usa apenas o aplicativo WhatsApp Business. Habilite a API oficial da Meta/BSP, verifique elegibilidade do número/coexistência com o app conforme o provedor e configure um número autorizado. Isso depende da conta comercial e das permissões da Meta; não foi feito automaticamente.

Configure segredos separados de staging/produção, listados em `supabase/.env.example`: App Secret, Verify Token longo/aleatório, Access Token, Phone Number ID. Publique `whatsapp-webhook`, `whatsapp-send` e `integration-worker`. A URL do webhook é a da Edge Function; a validação usa o desafio de assinatura da Meta e HMAC-SHA256 nos bytes brutos para POST.

Gere o link de delivery em **QR e autoatendimento**, usando o domínio HTTPS publicado, e configure `WHATSAPP_MENU_URL`. O FAQ responde horário/endereço geral/atendimento e encaminha pedidos ao cardápio. O handler inicial aceita mensagens de texto; mídia deve ser atendida por humano no canal apropriado. Ele não usa um LLM para interpretar valores ou fazer estornos.

Configure um agendador a cada minuto para chamar `integration-worker` com `X-Worker-Secret`, usando segredo aleatório `INTEGRATION_WORKER_SECRET` no cofre da plataforma, nunca no frontend/Git/SQL publicado. Sem variáveis Meta, o worker retorna indisponibilidade sem consumir jobs. Não exponha o endpoint a chamadas anônimas sem o segredo.

Respostas livres ficam dentro da janela do WhatsApp; fora dela, cadastre e obtenha aprovação do template de status (dois parâmetros de corpo: número do pedido e status), configure seu nome/idioma, e respeite o opt-in. O código usa a versão Graph configurável (`v23.0` por padrão); valide a versão suportada e o template na conta real. As mensagens têm entrega pelo menos uma vez: timeout após envio pode duplicar uma notificação. O sistema não transforma essa duplicação em novo pagamento ou ticket. Após oito falhas, admin pode autorizar retry com justificativa.

## 4. Edge/frontend e observabilidade

Publique `staff-admin` para criação de funcionários pelo painel e use `npm run build`/Vercel conforme `vercel.json`. As SPA routes e cabeçalhos estão versionados. Nenhum deploy foi executado neste chat.

Sentry é opcional por `VITE_SENTRY_DSN` público; não envia nada se vazio. SDK é carregado sob demanda, sem replay, traces, dados de usuário, requisições ou query strings (que poderiam conter tokens de acompanhamento). Acrescente somente o host exato do seu DSN à CSP `connect-src` antes de habilitar; não libere `*`. Valide recebimento em staging. Pooler hospedado, backups e rollback em `deploy.md`.

## 5. Homologar antes da produção

Com contas reais, verifique RLS/termais em dois dispositivos; cinco erros com troca de conta e bloqueio de 180 s; 10 min sem entrada humana; reabertura da página bloqueada; leitura de contatos negada à cozinha/outro caixa; total/preço/modificador; estoque por receita; duplicação de pedido/pagamento; sangria/fechamento; Pix conferido e devolução manual; QR do cliente; KDS/reconexão; autorização de templates e consentimento; webhook inválido/repetido; restauração de backup e rollback. Estes resultados não são substituídos por mocks do navegador ou pelo PostgreSQL local.

## 6. Login touch, Fast-Pass e KDS tático

Em projeto já na versão 011, aplique **somente as incrementais 012, 013 e 014**, em ordem; não repita o seed nem as migrações antigas. Estes arquivos usam o esquema operacional em inglês, compatível com o frontend atual. Não misture com os scripts independentes de `supabase/sql_editor/`.

- **012 / Fast-Pass:** publique `fast-pass` com `verify_jwt=false`, conforme config.toml. O endpoint exige origem cadastrada em `APP_ALLOWED_ORIGINS`, token de terminal cadastrado pelo admin e PIN pessoal válido. A chave `service_role` é usada só no servidor. O endpoint gera uma prova Auth de uso único sem enviar e-mail, valida a sessão pelo Auth e vincula o `session_id` ao terminal por desafio curto e descartável. Não há JWT fabricado no navegador. Admin entra com e-mail/senha; funcionários podem entrar diretamente por PIN, com redirecionamento pelo perfil verificado.
- Cadastre o navegador em **Equipe e acessos → Terminais**, defina **PINs distintos** para funcionários ativos e teste os dois cargos em staging. PIN legado duplicado é recusado pelo Fast-Pass; redefina-o pelo admin. O bloqueio de cinco falhas/180 segundos compartilha o contador com o desbloqueio de sessão e não é zerado ao trocar de conta ou recarregar a página. Uma sessão criada por PIN não se transforma em sessão de admin após promoção; exige novo login por senha.
- **013 / Demanda:** publica `kitchen_station_load`, com três linhas contendo apenas quantidades, tempos e parâmetros operacionais. Caixa, admin e cozinha recebem a atualização Realtime e reconciliação a cada 10 segundos. Tickets continuam separados no servidor e protegidos por praça. KDS passa a verde abaixo de 10 minutos, amarelo de 10 até 20 e vermelho acima de 20.
- No KDS do admin, **Ajustar capacidade das praças** permite calibrar referência de segundos por item, capacidade simultânea e limite de fila. O limite inicial da chapa é 15; 16 itens geram Alta Demanda. A média medida é a duração de preparo dividida pelas unidades, ponderada em até 100 tickets recentes dos últimos 30 dias, no último recálculo. Sem amostra, o painel indica **Referência inicial**. A estimativa do próximo item é o maior entre a média de um item e `(fila + preparo + 1) × média / capacidade`, arredondada para minutos. No PDV, a previsão do carrinho substitui esse `1` pelas quantidades de cada praça e usa o maior tempo entre elas. Inclui itens em preparo integralmente e é uma aproximação operacional, sem garantia de prazo. Não prevê trânsito, frete ou prazo contratual de entrega.
- **014 / DRE gerencial:** registra despesas com idempotência/auditoria e captura o custo unitário dos insumos nas novas baixas. Registros anteriores não são reescritos; o relatório identifica custos históricos estimados pelo custo atual. Produtos sem ficha impedem apresentar um resultado como completo. Sangria/suprimento não são classificados como despesa. Estornos acompanham as vendas do período em seu estado atual; a tela não é um fechamento contábil oficial.

Publique também as versões atualizadas de `staff-admin` e `integration-status`, que usam o contexto autenticado da migração 012 para impedir promoção de sessão criada por PIN. Faça a sequência banco → funções → frontend. A UI exige alvos touch de pelo menos 48px (teclado 64px), tema aço/laranja-fogo, animações suaves e respeito a `prefers-reduced-motion`.

Validação local: `npm run validate`, `npm run test:db`, `deno check supabase/functions/fast-pass/index.ts`, `python3 tests/ui_smoke.py` e `python3 tests/tactical_ui_smoke.py`. Os testes SQL executam PostgreSQL real descartável; Auth/REST/WebSockets dos testes de interface são simulados. A emissão real de sessão deve ser homologada no Auth do projeto antes da produção; nenhum projeto hospedado foi alterado aqui.
