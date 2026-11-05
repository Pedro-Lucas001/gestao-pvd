# Planeta Lanches

Painel web responsivo para organizar o atendimento e a cozinha, com login individual e dois perfis. Versão inicial para desenvolvimento e validação com a equipe.

## Executar

Requer Python 3.10 ou superior. O backend usa apenas a biblioteca padrão; o frontend requer Node.js e as dependências do package-lock.json.

Na raiz do repositório:

```bash
npm ci
npm run build
python3 server.py
```

A aplicação escuta na porta 3000, em loopback por padrão. No primeiro acesso, cadastre o administrador; não existe senha padrão. Faça esse cadastro em ambiente privado antes de disponibilizar o servidor. Para acesso na rede da loja, configure `HOST=0.0.0.0` e use uma implantação com HTTPS. Em HTTPS, defina `PLANETA_SECURE_COOKIE=1`. A implantação pública ainda exige revisão de segurança, estratégia de recuperação de acesso e backups.

`PORT` altera a porta. `PLANETA_DB` permite definir outro arquivo SQLite. O padrão é `.data/planeta.db`, ignorado pelo Git. Preserve esse arquivo; contém usuários, sessões e pedidos. Não compartilhe nem versione o banco. Para uma cópia consistente enquanto o servidor está em execução, use a API de backup do SQLite.

## Perfis

| Recurso | Administrador | Funcionário |
| --- | --- | --- |
| Visão geral e recebimentos | Sim | Não |
| Criar e consultar pedidos, inclusive valores | Sim | Sim |
| Acompanhar cozinha e avançar etapas | Sim | Sim |
| Confirmar recebimento manualmente | Sim | Não |
| Cancelar pedido | Sim | Não |
| Cadastrar, bloquear e reativar funcionários | Sim | Não |
| Consultar integrações | Sim | Não |

O primeiro administrador é cadastrado uma única vez. Funcionários são cadastrados em **Equipe e acessos**. O bloqueio revoga as sessões da pessoa. Senhas são armazenadas como hashes scrypt, e as sessões usam cookies HttpOnly, SameSite e validade de 12 horas. As permissões são verificadas no servidor; ocultar opções na interface não é a barreira de segurança.

## Pedidos

1. Cadastre o cliente, o canal, os itens e o método de pagamento.
2. O pedido aguarda pagamento e não entra na cozinha.
3. O administrador confere o recebimento fora do sistema e confirma manualmente.
4. A equipe avança por **Na fila → Em preparo → Pronto → Concluído**.

Os preços vêm do catálogo por item; os totais são calculados no servidor em centavos. O painel atualiza a cada 15 segundos. Pedidos cancelados não são apagados. Cancelamento não efetua estorno.

**Ainda não implementado:** confirmação automática Pix, recebimento de mensagens WhatsApp, impressão automática, estoque, relatórios financeiros completos e recuperação de senha. O canal WhatsApp apenas identifica pedidos digitados pela equipe. Nenhuma integração é simulada como se estivesse conectada.

## Validar

```bash
python3 -m unittest discover -s tests -v
npm run lint
npm run build
```

Os testes iniciam um servidor real com banco temporário e verificam permissões, bloqueio de acesso, proteção CSRF, validação, cálculo de total, bloqueio antes do pagamento e o ciclo de preparo. Não alteram o banco da aplicação.
