# Entrega, impressão e acompanhamento

## O que muda

No checkout, a entrega oferece Pix, dinheiro e cartão na entrega (crédito ou débito). O cartão online existente continua separado. A maquineta física não usa a integração de cartão online.

- **Cartão na entrega:** 6% sobre produtos + taxa de entrega, arredondados uma única vez para centavos. Exemplo: R$ 30,00 de produtos + R$ 5,00 de entrega = base de R$ 35,00; acréscimo R$ 2,10; total R$ 37,10. O servidor calcula o preço; valores do navegador não substituem o preço do catálogo. O resumo mostra o acréscimo antes da confirmação.
- **Pix:** código no acompanhamento e envio pela fila oficial do WhatsApp quando autorizado. É necessário configurar Pix/provedor, Meta e o worker. O código não representa recebimento confirmado.
- **Dinheiro:** o cliente informa se precisa de troco e para qual valor. O valor precisa cobrir o total. Troco não é receita.
- **Entrega:** nome, WhatsApp, endereço completo e ponto de referência obrigatórios. E-mail é obrigatório para o provedor eletrônico; cartão presencial e dinheiro permitem e-mail opcional.

Ao criar uma entrega em Pix, dinheiro ou cartão presencial, a transação grava o pedido, baixa os insumos, cria os trabalhos da cozinha e enfileira a comanda. Uma falha desfaz toda a transação. **O pagamento permanece a receber.** Retirada e cartão online conservam suas regras anteriores de aceite/confirmação antes do preparo. A loja continua controlando abertura dos pedidos e disponibilidade de entrega.

O atendente assume o pedido com turno aberto. Para dinheiro, registra o recebimento físico conferido. Para cartão na entrega, confere o valor aprovado na maquineta e registra um identificador único/NSU (8–100 caracteres) e justificativa. Não use o mesmo identificador para duas transações. Cartão presencial entra na receita recebida, sem aumentar a gaveta de dinheiro. O sistema só permite concluir depois de quitar o valor. Marcar “saiu para entrega” é permitido com pagamento pendente.

Alterações continuam sujeitas à aprovação dos setores envolvidos. Uma adição a pedido já pago exige Pix complementar antes de liberar o preparo revisado. Uma cobrança eletrônica já aberta impede alterações concorrentes até sua conciliação. Em cartão presencial ainda não recebido, a revisão recalcula os 6% e a nova comanda identifica a revisão.

## Acompanhamento do cliente

Após enviar, o cliente abre `/pedido#acompanhar=<segredo individual>` e pode copiar o link privado. A tela consulta o status a cada 5 segundos e mostra fila, preparo, pronto, saída para entrega e conclusão, além do histórico com horários e do pagamento separado. As etapas vêm das ações da equipe. Não há mapa/GPS ou prazo de entrega inventado.

O link também acompanha os avisos de status no WhatsApp. Novos pedidos guardam o segredo apenas em tabela privada para o worker montar esse link; o hash permanece no pedido público. Contatos não são devolvidos pela consulta de acompanhamento. Quem recebe o link pode acompanhar e solicitar uma alteração dentro das regras; compartilhe somente com quem deve ter esse acesso.

Fora da janela de atendimento, os avisos dependem de modelos Meta aprovados. `WHATSAPP_ONLINE_STATUS_TEMPLATE` mantém dois parâmetros (número e status com link). `WHATSAPP_ONLINE_PAYMENT_TEMPLATE` mantém três parâmetros (número, valor e Pix copia e cola). O aviso de recebimento/status traz o link; o aviso Pix é separado e traz a cobrança. Sem consentimento, não há envio WhatsApp; o site continua funcionando.

## Implantação incremental

1. Revisar e aplicar **somente** `supabase/migrations/20261108150436_delivery_checkout.sql` no contrato atual. Não executar os instaladores de projeto vazio na produção já instalada. Não aplicar `bootstrap.sql` ou fixtures em produção.
2. Publicar `customer-api`, `integration-worker` (inclui o código compartilhado de notificações) e a nova função `print-agent`, esta com `verify_jwt=false`. Ela exige sua própria credencial de impressão. Atualizar também o frontend após o banco e as funções.
3. Verificar os segredos já documentados em `supabase/.env.example`: `APP_ALLOWED_ORIGINS`, `PUBLIC_SITE_URL`, Pix/provedor, Meta/modelos e `WORKER_SECRET`. Agendar `integration-worker` de forma autenticada para escoar a fila. Nenhuma chave privada vai para `VITE_*`.
4. No admin → Pedidos online, revisar abertura, entrega e opção cartão na entrega. Os flags atuais de abertura não são alterados pela migração incremental. Só abrir para pedidos reais depois da homologação.
5. Instalar o agente descrito abaixo. Testar uma entrega controlada de cada forma de pagamento, o cupom físico e todas as etapas. Não usar a aprovação de CI como evidência de impressão física ou de mensagem real entregue.

## Instalação do agente de impressão (Windows)

A impressora ainda será escolhida. A implementação usa o **driver instalado no Windows**, aceitando impressoras USB ou de rede que funcionem com ele. Homologar modelo, margens, largura e alimentação/corte com o equipamento real; não promete corte automático. Impressoras que exigem protocolo próprio sem driver Windows precisam de um adaptador adicional.

1. Instalar a impressora e imprimir a página de teste no Windows. Instalar Node.js LTS. Copiar a pasta `scripts/print-agent` do repositório para o computador da loja.
2. Admin → Pedidos online → **Impressão automática dos pedidos** → gerar credencial. A geração desativa a credencial anterior. Copiar a credencial exibida uma única vez; não enviar por chat. Ela permite somente retirar e confirmar cupons, sem editar pedido, equipe ou dinheiro.
3. Executar `scripts/print-agent/Setup-Printer.ps1` no PowerShell como o usuário que usará a impressora. Informar URL pública do Supabase, chave publishable pública, nome exato da impressora, papel 58 ou 80 mm e a credencial do agente (entrada oculta). A configuração fica em `%LOCALAPPDATA%\PlanetaLanchesPrint`, com acesso restrito ao usuário. Não usar `service_role`.
4. Executar `node scripts/print-agent/agent.mjs`. Nenhuma instalação npm é necessária para o agente. Mantê-lo aberto e o computador ligado. Para iniciar no login do Windows, criar uma tarefa no Agendador com o mesmo usuário e o caminho absoluto de `node.exe` + `agent.mjs`; não executar simultaneamente duas instâncias.
5. Confirmar no painel a última conexão, depois enviar um pedido controlado. Verificar no papel número/revisão, itens, personalizações, total, pagamento pendente, endereço, referência e WhatsApp. Cartão deve destacar **LEVAR MAQUINETA** e os 6%; dinheiro deve destacar o troco.

O agente consulta a cada 5 segundos. A fila suporta reconexão e não duplica pela repetição da criação do pedido. A confirmação **“Enviado ao Windows”** comprova a submissão ao spooler, não a saída física do papel. Falha, encerramento inesperado ou perda de confirmação deixam o job para conferência; não há repetição automática ambígua. Depois de verificar a impressora, o admin pode solicitar segunda via com justificativa e confirmação explícita. A via fica identificada como segunda via. Se houve encerramento inesperado, verificar que não há outro processo do agente rodando antes de remover `%LOCALAPPDATA%\PlanetaLanchesPrint\agent.lock`.

Revogar a credencial no admin se o computador for perdido/trocado. Não copiar a configuração para computadores de clientes. Logs do agente não incluem token, telefone, endereço nem conteúdo do pedido. O arquivo temporário de cupom é removido após a tentativa; o diário local conserva apenas identificadores de controle.

## Validação

`npm run validate` inclui os testes de cupom, troco, total e proteção contra comandos de controle no texto. `npm run test:db` inclui `supabase/tests/delivery.sql`: preços canônicos, arredondamento, campos obrigatórios, preparo pendente sem receita fictícia, estoque/recibo idempotentes, recebimento de cartão, conclusão, histórico, privilégios, claims e falha ambígua da impressão. Os testes usam banco descartável; não chamam Meta, não cobram dinheiro e não imprimem no estabelecimento.
