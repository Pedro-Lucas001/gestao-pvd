# Segurança avançada, auditoria e privacidade

## Auditoria automática

`audit_log` tem `actor_id`, `actor_kind`, `action`, `created_at`, `amount_cents`, `quantity_delta`, `entity_type/entity_key` e `justification`. A unidade monetária é centavos. Não some valores de eventos como se fossem um extrato: um estorno e o cancelamento correspondente são eventos distintos da mesma operação.

Triggers registram cancelamento de pedido, desconto, estorno confirmado, estoque/custo/cadastro de insumos, receitas/modificadores, produto/preço, sangria/suprimento/devolução em caixa, abertura/fechamento e alteração de acesso. RPCs também registram PIN trocado, terminal cadastrado/revogado, lockout, anonimização, consulta de relatório, atribuição e retries autorizados. A confirmação manual de Pix registra o administrador e a justificativa. Integrações sem usuário humano usam `actor_kind=integration/system`; o pedido de estorno mantém `requested_by` apontando ao responsável.

As alterações financeiras são comandos transacionais, não `UPDATE` livre pelo navegador. Sem justificativa válida a transação sensível falha. Confirmação, estoque, ticket e outbox são atômicos; uma falha não deixa metade da operação gravada. Auditoria não armazena senhas, PINs, tokens, cartão, endereço ou snapshots de clientes. Não inclua dados pessoais nas justificativas.

Nenhum perfil da aplicação recebe `UPDATE/DELETE/TRUNCATE` de auditoria. A service role também não pode escrever diretamente nesses logs. Triggers de imutabilidade bloqueiam UPDATE/DELETE/TRUNCATE comuns, inclusive executados pelo proprietário da tabela. **Não existe imutabilidade absoluta contra um dono de banco que possa remover triggers, alterar funções ou restaurar backup.** Restrinja SQL Editor/DDL, use MFA na plataforma, segregue responsáveis e, se necessário, exporte evidências para armazenamento WORM/conta separada. Não há WORM externo configurado nesta entrega.

## PIN: cinco erros / três minutos

O admin cadastra o navegador em `/equipe`; um token de 256 bits fica no dispositivo e apenas seu SHA-256 fica no schema privado. O usuário ainda se autentica com e-mail/senha. Esse token identifica o terminal, não concede papel nem substitui login.

O servidor bloqueia o registro do terminal durante a validação, serializa tentativas e incrementa um contador comum a todos os operadores daquele dispositivo. Cinco erros consecutivos geram `locked_until = now() + 3 minutes`. Trocar conta, JWT, aba ou recarregar não cria um novo terminal. Um acerto zera a sequência; o PIN é verificado com bcrypt. Há também limitação por usuário para reduzir tentativa em vários dispositivos. Cadastro de novo terminal exige admin e gera auditoria; terminal revogado perde suas leases.

O countdown da interface é informativo. O PostgreSQL decide quando aceitar novamente; alterar o relógio do navegador não remove o bloqueio. É necessário manter o navegador/dispositivo sob controle da loja. Reinstalação ou limpeza do armazenamento exige novo cadastro por admin.

## Inatividade: dez minutos

`useIdleLock` conta entrada real de pointer/teclado/roda/toque (`isTrusted`), com relógio de parede e monotônico, checando também retorno de aba. Atualizações do servidor e eventos sintéticos não reiniciam o contador. Após 10 min a aplicação remove o conteúdo operacional e exige PIN. O estado do bloqueio persiste na sessão do navegador, inclusive para o admin após recarregar.

Leases do servidor duram 10 min e o heartbeat só renova uma lease válida quando há entrada do operador, com limite de frequência. Lease expirada não é ressuscitada por heartbeat. Cozinha também exige lease para ler/alterar tickets. O admin mantém privilégios do papel no banco; seu auto-lock é proteção da interface/terminal, não rebaixamento de um JWT administrativo roubado. Uma reautenticação completa permite recuperar o admin e configurar seu PIN; PIN não é login público.

Sem conexão, bloqueio local ocorre mesmo que a revogação no servidor não possa ser confirmada. A lease anterior expira no servidor. Para risco de token roubado, adicione os controles de sessão/MFA/revogação da plataforma; não confunda auto-lock visual com proteção contra um sistema operacional comprometido.

## Delivery e LGPD/RGPD

Contato fica em `customer_contacts`, separado de `orders` e de tickets. RLS permite:

- Admin ativo: acesso de gestão.
- Caixa ativo, destravado e atribuído: somente contato de pedido pago em andamento (`queued/preparing/ready`). Após entrega/cancelamento deixa de enxergar.
- Cozinha, outro caixa e anônimo: nenhuma linha de contato.

A fila de novos pedidos externos expõe só número/canal/valor; assumir um pedido exige caixa aberto e gera auditoria. KDS recebe `Pedido #N`, produtos/modificadores e observações culinárias, sem nome de contato, telefone, e-mail ou endereço. Dados privados não são publicados no Realtime. Observações livres não devem conter dados pessoais; o formulário separa endereço/telefone dos detalhes de cozinha.

Não existe exportação de base para funcionário da cozinha. Qualquer dado legitimamente mostrado a alguém pode ser copiado por essa pessoa; RLS controla a autorização, não impede capturas de tela ou um sistema operacional comprometido. A atribuição e o uso de terminais devem ser supervisionados.

O cliente escolhe separadamente receber atualizações no WhatsApp. Não há opt-in de marketing. O token de acompanhamento é pessoal e revela só situação/número/total/QR daquele pedido, nunca a base de clientes. Links de mesa/delivery têm revogação, expiração, limites de pedidos e não são credenciais administrativas.

`anonymize_customer` permite anonimizar contato de pedido encerrado, preservando documentos financeiros e trilha mínima. Retenção, base legal, atendimento de direitos, contratos com operadores e dados já enviados ao banco/Meta exigem política da loja; a função não declara conformidade jurídica universal nem apaga mensagens de provedores externos. Nunca coloque contatos em relatórios/Sentry/auditoria. O Sentry opcional elimina URL/query strings, formulário, request, usuário, breadcrumbs e replay.
