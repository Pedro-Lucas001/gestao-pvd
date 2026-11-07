# Implantação e operação

Use [activation.md](activation.md) para a sequência completa. Esta entrega versiona código/configuração; não cria projetos, não envia mensagens, não transfere dinheiro e não faz deploy automaticamente.

## Staging e produção

Crie projetos Supabase separados e destinos/variáveis Vercel isolados. Nunca aponte previews para o banco de produção. No frontend: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_APP_ENV`, opcional `VITE_SENTRY_DSN`. Estes são valores públicos incorporados no bundle. Chaves de serviço, Pix, tokens Meta, senha, PIN e worker secret ficam exclusivamente nos segredos Supabase.

Mantenha signup público desativado, senhas fortes e acesso à plataforma restrito. MFA administrativo da aplicação ainda exige o fluxo de desafio AAL2; ativá-lo no Auth sem implementar a tela/desafio não substitui essa etapa. O administrador entra com e-mail/senha. Funcionários podem usar e-mail/senha ou PIN via Fast-Pass em terminal cadastrado; o papel é verificado no servidor. Configure MFA nas contas de administração da plataforma e homologue o que for adotado para a loja.

## Banco

As migrations são progressivas, da 001 à 018. Em projeto totalmente vazio, há também o instalador transacional [01_instalacao_nova.sql](../supabase/activation/01_instalacao_nova.sql), que inclui seed e recusa estruturas existentes; não executar os dois caminhos no mesmo banco. Faça backup e aplique primeiro em staging. `supabase/tests/bootstrap.sql` é um fixture de testes em PostgreSQL vazio: **nunca** aplicar em projeto real. `supabase db reset` é só para desenvolvimento local descartável. `supabase db push` e importação inicial de seed exigem vínculo com o projeto correto e credenciais de administração fornecidas com segurança pelo usuário.

Não reutilize contas/tabelas do SQLite sem migração conferida. Não foram alterados os dados antigos. Planos de retenção, saldos de abertura, histórico de pagamentos, usuários e receitas reais precisam de conferência na migração de negócio.

## Pooling

Frontend usa REST/Realtime, não conexão SQL direta. `supabase/config.toml` habilita pooler **local** transaction com 15 conexões/100 clientes, valores iniciais de desenvolvimento. Isso não muda o Supavisor hospedado. Configure o pooler hospedado pelo painel do projeto, dimensione pelo plano/carga e meça picos reais. Workers SQL externos devem usar o Transaction Pooler do painel com TLS validado, concorrência limitada e política de prepared statements compatível. Não invente hostname, senha ou porta; a conexão vem do serviço.

## Frontend Edge

Vercel: `npm ci`, build `npm run build`, output `dist`, rotas SPA e cabeçalhos em `vercel.json`. Há chunks separados de React, Supabase, QR e módulos administrativos; gestão e monitoramento são carregados sob demanda. TLS/CDN/rollback vêm da plataforma após configurar o projeto. Nenhum deploy Vercel foi iniciado.

A CSP permite REST/WebSocket Supabase padrão. Adicione destinos exatos se usar domínio Supabase customizado ou Sentry; não substitua por `*`. Ajuste Site URL e redirects Auth aos domínios corretos (sem wildcard de produção). Teste `/pedido`, `/pdv`, `/cozinha` e rotas restritas digitadas diretamente.

## Funções e jobs

Publique as funções conforme os `verify_jwt` de `supabase/config.toml`. Funções de usuário exigem JWT e validam o usuário/perfil; checkout público exige capacidade de acompanhamento; webhook Meta valida assinatura; worker exige `X-Worker-Secret`. A ausência de JWT em webhook/worker não significa ausência de autenticação.

Configure as variáveis exemplificadas em `supabase/.env.example` no painel seguro do projeto e um agendador autenticado para o worker. Não coloque segredos em migrações SQL de agendamento nem em logs. Habilitar cron/Edge/scheduling e Meta depende do projeto/conta, não foi feito localmente.

## Monitoramento, recuperação e disponibilidade

Sentry opcional usa SDK instalado, sem replay/traces/coleta padrão, e transmite só erro genérico/área. Remove usuário, URL/query strings, request/breadcrumbs e dados de formulário para não vazar tokens ou delivery. Sem DSN não envia. Configure o host exato do DSN na CSP e teste em staging antes de afirmar que está monitorando produção.

Error Boundaries isolam módulo e modificadores; handlers capturam erros assíncronos. Navegador offline bloqueia envios e pagamentos; disponibilidade de rede não prova que Supabase/Meta estão saudáveis. Reenvio exige a mesma chave/corpo quando o resultado é desconhecido. Bloqueio local pode ocorrer sem revogação imediata no servidor durante queda; a lease expira e não pode ser reativada por heartbeat após vencida.

Habilite backup/PITR conforme o plano e ensaie restauração. Não faça rollback destrutivo de dados financeiros para acompanhar uma versão antiga de UI. Use migrações compatíveis e valide a versão de frontend antes de reverter. RLS, auditoria e tokens não substituem proteção física do terminal, permissões de DBA, política LGPD, TLS, conferência de caixa ou homologação dos fornecedores.

## Cardápio público e acesso interno

Consulte [access-and-public-menu.md](access-and-public-menu.md) para a matriz de permissões e a ativação da migração 015. O início e `/cardapio` são o mostruário público; `/login` e `/sistema` são exclusivos da equipe.
