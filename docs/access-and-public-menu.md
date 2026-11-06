# Cardápio público e área da equipe

| Rota | Uso | Acesso |
| --- | --- | --- |
| `/` e `/cardapio` | Mostruário, busca, categorias, ingredientes e preços | Público, sem login |
| `/login` | Entrada da equipe | Contas pessoais, sem cadastro público |
| `/sistema` | Entrada da operação | Redireciona pelo perfil verificado |
| `/pdv` | Vendas, comanda e caixa | Caixa e administrador |
| `/atendimento` | Atendimento e delivery atribuído | Caixa e administrador |
| `/cozinha` | Fila do setor atribuído | Cozinha e administrador |
| `/dashboard`, `/relatorios`, `/dre` | Indicadores e finanças | Administrador |
| `/estoque`, `/catalogo`, `/pagamentos` | Estoque, preços e conciliação | Administrador |
| `/equipe`, `/auditoria`, `/links`, `/integracoes` | Gestão de acessos e serviços | Administrador |

`/previa` redireciona ao cardápio. O cliente não recebe controles de caixa nem PDV de demonstração. `/pedido` continua sendo o checkout por link específico já existente, separado do mostruário. Não há compra nem coleta de dados pessoais no cardápio.

## Autenticação e autorização

O login não compara PINs fixos no navegador. E-mail e senha usam Supabase Auth; o PIN do funcionário é validado pela função `fast-pass`, com terminal cadastrado, limite de tentativas e perfil ativo. O administrador entra com e-mail e senha. Seu PIN serve para retomar o terminal e não para obter privilégios administrativos em um login de funcionário.

`src/auth/modules.js` governa os menus e as rotas. Perfis ausentes, desconhecidos ou não ativos não recebem acesso. No servidor, RLS e RPCs continuam verificando a função do operador e isolando caixas, setores e dados financeiros; esconder links não substitui essas verificações.

Em **Equipe e acessos**, o administrador consulta a matriz e cria contas individuais usando a função `staff-admin` já existente. A função valida o usuário e o perfil administrativo antes de usar a credencial de serviço. A criação requer a função publicada e `APP_ALLOWED_ORIGINS` com o domínio correto. Falhas parciais informam o que deve ser concluído na lista da equipe, sem apagar contas ou repetir a criação automaticamente.

## Ativação do cardápio real

1. Aplicar `supabase/migrations/202611060015_public_menu.sql` no projeto que já usa as migrations 001–014, primeiro em staging e depois conforme o processo de implantação da loja.
2. Publicar o frontend com `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` (ou a chave anon legada).
3. Conferir `/cardapio` sem sessão. Alterar um preço/ativação em **Catálogo e preços** e conferir a próxima consulta pública.

A migração cria somente `public_menu()`, sem alterar ou apagar registros existentes. A RPC retorna produtos ativos e apenas `id`, `name`, `category`, `description`, `price_cents`, `image_path`. Não concede leitura direta de tabelas a visitantes nem revela custos, estoque, equipe, clientes, pedidos ou relatórios. Usa `search_path` vazio e `EXECUTE` explícito para `anon` e `authenticated`.

A página pública não monta `AuthProvider` nem importa o cliente autenticado. A consulta usa apenas a chave pública; não lê storage nem transmite a sessão de um funcionário no mesmo navegador. Os produtos são atualizados a cada 60 segundos e quando a página volta a ficar visível.

Com o backend configurado, uma falha de consulta exibe erro e opção de tentar novamente; não troca preços reais por uma amostra silenciosa. Sem configuração, a página apresenta explicitamente um **cardápio de referência** e orienta confirmar preços no balcão. A migração 015 é necessária para publicar o catálogo administrado.

## Verificação

- `npm run validate`: lint, testes e build; inclui a matriz completa de rotas, projeção dos campos públicos, preços inválidos e busca por categoria/ingredientes.
- `npm run test:db`: inclui `supabase/tests/public_menu.sql` com role PostgreSQL `anon` real. Verifica produtos inativos, atualização de preços, campos permitidos e negação de tabelas e operações internas.
- Navegador: consulta e filtros sem login, entrada separada, rota interna sem sessão e retorno ao cardápio. A prévia local não valida credenciais reais nem instala migrations em produção.

## Referências

- [OWASP — Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html): menor privilégio, negação por padrão e validação por requisição.
- [Supabase — Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security): políticas no banco para acesso anônimo e autenticado.
