# Ativação — situação em 07/11/2026

Projeto Supabase: **Planeta-Lanches** (`qhtcyqsmjuwlhsrzjhqp`). Site: https://gestao-pvd.vercel.app/cardapio.

## Concluído

- Transição autorizada aplicada: oito tabelas antigas preservadas no schema privado `planeta_legacy_20261107`, com suas funções e dependências.
- Contrato 001–018 instalado e catálogo inicial com **47 produtos**. A API pública foi consultada via HTTPS com a chave publishable e retornou HTTP 200 e os 47 registros.
- Bucket `planeta-product-images` criado. Todas as tabelas públicas possuem RLS.
- Ajuste adicional de permissões aplicado: EXECUTE implícito de PUBLIC removido; ficam disponíveis sem login somente `public_menu`, `online_shop_config`, `checkout_menu`, `checkout_order` e `checkout_status`. Os GRANTs de operadores e serviço foram preservados e conferidos.
- **11 Edge Functions publicadas**, seguindo os `verify_jwt` do config.toml. Funções `eco-*` não foram publicadas.
- Variáveis públicas de produção configuradas na Vercel, sem credenciais privilegiadas no frontend. PRs 11 e 12 mesclados; publicação de produção READY.
- CI aprovado, incluindo testes de banco/RLS, recusa de instalação repetida, preservação/recusa de legado com dados, permissões de RPC e funções Deno. Navegador local com Auth/REST simulados validou o bloqueio por senha/PIN. A tentativa de navegador contra produção encontrou limitação de certificado do proxy deste ambiente; a verificação de produção utilizou HTTPS verificado e os metadados da Vercel.

## Operação ainda pausada

Pedidos e entrega permanecem desabilitados. Não há contas Auth nem administrador ativo na última conferência. A publicação das funções não configura automaticamente seus segredos.

Próximos passos pelo responsável no painel Supabase:

1. Em **Authentication → Users**, criar a conta individual do administrador com e-mail confirmado e senha escolhida pelo responsável. Não compartilhar a senha no chat. Ativar somente o UUID correto conforme [activation.md](activation.md).
2. Nas configurações de Auth, desabilitar cadastro público: a consulta de `/auth/v1/settings` ainda retornou `disable_signup=false`. O site não oferece cadastro de funcionários ao público, e contas sem perfil ativo não recebem acesso operacional.
3. Em **Edge Functions → Secrets**, cadastrar os valores públicos de configuração do servidor:

```dotenv
APP_ALLOWED_ORIGINS=https://gestao-pvd.vercel.app
PUBLIC_SITE_URL=https://gestao-pvd.vercel.app
```

A consulta OPTIONS de `customer-api` ainda retornou 403 sem essa origem cadastrada. O cardápio consulta diretamente a RPC pública e funciona independentemente dessas funções.

4. Cadastrar os terminais e os funcionários com PIN individual; revisar preços, fotos, estoque, custos, fichas e entrega antes de liberar pedidos.
5. Para Pix/cartão, WhatsApp e IA, cadastrar as credenciais da loja, homologar os provedores e configurar o agendamento autenticado do worker. O exemplo está em [supabase/.env.example](../supabase/.env.example). Nenhum pagamento ou mensagem foi enviado na ativação.

## Histórico e manutenção

O histórico remoto registra `initialize_current_contract_preserving_empty_legacy` e `restrict_implicit_public_rpc_execution`. O primeiro representa o bundle integral instalado, e não 18 entradas individuais da CLI. Reconciliar esse histórico antes de usar `db push`; não repetir instaladores, marcar arquivos sem conferência nem executar `db reset`.

Os avisos restantes sobre funções SECURITY DEFINER devem ser avaliados conforme os grants explícitos e as validações de cargo/capacidade. As cinco funções públicas acima são intencionais; não remover esses acessos para apenas zerar avisos do painel.
