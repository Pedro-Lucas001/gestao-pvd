# Implantação e configuração

Nenhum projeto Supabase, deploy Vercel, gateway Pix/TEF ou conta de WhatsApp foi criado/publicado por esta entrega. Todas as chaves e destinos precisam ser configurados nos serviços apropriados.

## 1. Dois ambientes reais e isolados

Crie dois projetos Supabase: `planeta-staging` e `planeta-production`, e dois destinos de Vercel (ou use ambientes separados com variáveis próprias e previews sem credenciais de produção).

| Variável frontend | Staging | Production |
| --- | --- | --- |
| `VITE_SUPABASE_URL` | URL do projeto staging | URL do projeto production |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | publishable ou anon pública staging | publishable ou anon pública production |
| `VITE_APP_ENV` | `staging` | `production` |

São valores públicos incorporados no bundle. **Nunca** coloque `service_role`, `sb_secret_*`, chave PSP, PIN, senha, connection string ou chave de assinatura em variável `VITE_*`. O código também recusa chaves secretas modernas e JWT legado com role diferente de anon. A segurança depende de RLS, não do sigilo da chave pública. Cada preview deve usar apenas staging ou permanecer em prévia visual sem backend.

Em desenvolvimento, copie `.env.example` para `.env.local` e preencha apenas os valores públicos. Esses arquivos são ignorados pelo Git. Credenciais do Supabase CLI ficam no gerenciador/secret do CI; nunca em scripts versionados.

## 2. Aplicar banco e criar primeiro administrador

Instale o Supabase CLI oficial e autentique com a sua conta pelo fluxo seguro do serviço. Os comandos são templates documentados, não foram executados contra um projeto remoto:

```sh
supabase link --project-ref SEU_PROJECT_REF_STAGING
supabase db push
```

O seed deve ser aplicado explicitamente na primeira configuração pelo SQL Editor ou CLI com inclusão de seed; `supabase db reset` aplica seed **somente no ambiente local descartável**. Não rode reset em produção. `supabase/seed.sql` usa `ON CONFLICT DO NOTHING`, para não sobrescrever preços já editados; importe uma vez e confirme os 47 produtos.

No dashboard Supabase Auth, mantenha **cadastro público desativado**, crie sua conta administrativa com senha forte de pelo menos 10 caracteres e confirme o e-mail. Somente no SQL Editor do projeto correto, promova essa conta após verificar seu UUID:

```sql
update public.profiles set role='admin',active=true where id='UUID_REAL_DA_SUA_CONTA';
```

Crie as contas de funcionários pelo painel Auth (não compartilhe a senha do administrador), ative-as em `/equipe` ou pelo RPC `manage_staff`. Caixa exige PIN cadastrado por admin via `set_staff_pin`. Cozinha exige setor. Não há PIN ou senha padrão. Ative MFA para administradores no Supabase antes da produção e evolua o fluxo de login para desafiar o segundo fator; a interface inicial implementa e-mail/senha, não o desafio MFA completo.

Para desenvolvimento com toda a stack Supabase local: `supabase start` e `supabase db reset`, depois use a URL e chave anon locais em `.env.local`. O pooler local está definido em `supabase/config.toml`; a chave e URL serão as do seu CLI local, não as de produção.

## 3. Edge Functions e integrações

`payment-intent` valida JWT e permissões pelo RPC do usuário; `provider-webhook` não usa JWT de usuário, mas exige verificação criptográfica do gateway antes de qualquer escrita. O adaptador em `supabase/functions/_shared/gateway.ts` ainda lança `PAYMENT_GATEWAY_NOT_CONFIGURED`. Isso é intencional: não há PSP nem TEF contratado/configurado. Credenciais Supabase server-side são fornecidas às funções pelo Supabase; não entram no frontend.

Depois de implementar e homologar o provedor, configure `APP_ALLOWED_ORIGINS` com os domínios exatos de staging/produção, chaves do PSP e segredos de webhook por `supabase secrets set`/painel seguro. Use credenciais de sandbox no staging. Não habilite assinatura genérica inventada: cada provedor tem algoritmo, cabeçalhos e políticas próprias. Homologue assinatura inválida, replay, timestamp vencido, moeda/recebedor incorretos, valores divergentes, duplicação, timeout e reconciliação.

Use `supabase functions deploy payment-intent` e `supabase functions deploy provider-webhook` apenas após essa configuração. As funções atuais respondem indisponibilidade de integração e não cobram. Certifique-se de que o deploy manteve os requisitos JWT de `config.toml`; tokens não substituem a RLS das RPCs.

## 4. Hospedar frontend no Edge

Importe o repositório na Vercel, escolha Vite e configure as variáveis públicas por ambiente. `vercel.json` define build, SPA rewrites e cabeçalhos de segurança; `npm ci` + `npm run build` gera `dist`. A Vercel fornece CDN, TLS e versões de deploy para rollback. Nenhum deploy foi iniciado aqui.

Configure o domínio final no Supabase Auth (Site URL e redirects exatos; não wildcard em produção). A CSP permite apenas o domínio padrão `*.supabase.co` para REST/WebSocket. Se usar domínio customizado do Supabase ou Sentry, acrescente **somente os destinos exatos necessários** em `connect-src`. Evite liberar `*` ou scripts inline. A configuração deve ser validada no domínio real após deploy, inclusive rotas digitadas diretamente como `/pdv` e `/estoque`.

## 5. Pooling e conexões

O navegador usa REST/Realtime do Supabase, nunca uma conexão PostgreSQL direta. Para workers/server-side que precisarem de SQL, use o connection string **Transaction Pooler (Supavisor)** apresentado no painel do projeto, TLS verificado, pool pequeno (ex.: 5 por worker), timeout e limite de concorrência. Não invente hostname, porta, senha ou certificado: copie a conexão segura do projeto pelo painel. Prepared statements nomeados dependem de suporte do modo transaction e devem ser desativados no driver quando exigido pelo Supabase. Migrações usam a conexão apropriada do CLI, separada do tráfego da aplicação.

`supabase/config.toml` habilita o pooler **local**, mas não muda configurações do projeto hospedado. Ajuste limite de clientes/pool conforme plano e carga observada; valide com teste de pico antes de produção. Não foi possível configurar ou medir Supavisor hospedado sem projeto.

## 6. Observabilidade, backup e recuperação

`reportError` recebe apenas o tipo de erro e a área, sem corpo de pedido, dados de cartão, senha, token, PIN ou e-mail. `installReporter` permite conectar Sentry (SDK opcional, não instalado/configurado nesta entrega). Configure `beforeSend`, desligue replay de sessão e gravação de inputs no PDV, restrinja ambiente/release e adicione o destino exato à CSP. Error Boundaries no workspace e modificadores impedem falhas locais de derrubar o restante da tela; boundaries não capturam eventos assíncronos, tratados nos handlers.

Habilite backup/PITR conforme o plano, ensaie restauração em staging, meça consultas com índices e mantenha procedimento de rollback frontend + migração progressiva. Não faça rollback destrutivo de pagamentos para acompanhar uma versão de UI. Antes da operação real: homologar fluxo dinheiro, reconciliação, fluxo PIN/turno, RLS com contas reais, atualização de cargo, rede intermitente e KDS em dois dispositivos.
