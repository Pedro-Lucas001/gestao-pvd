# Opções do cardápio

Hambúrgueres e dogs na chapa abrem uma janela de personalização antes de entrar no carrinho. Os adicionais ativos aparecem dentro do lanche, com preço; deixam de ser produtos avulsos no mostruário. Cada escolha acrescenta uma unidade por lanche. Ao pedir dois lanches iguais com bacon, entram dois adicionais de bacon. Para escolhas diferentes, adicionar o lanche novamente com outra personalização.

O cliente envia apenas IDs dos produtos/adicionais e escolhas permitidas. O servidor recupera preços atuais, multiplica a quantidade e expande os adicionais em linhas identificadas com o lanche de origem. Isso mantém a associação no acompanhamento, cozinha, comanda e pedido revisado, e reutiliza a baixa de estoque e os custos de cada produto. Ingredientes do adicional dependem da ficha técnica cadastrada para esse adicional. A falta de ficha continua aparecendo como cobertura incompleta de custos.

O cardápio informa carnes industrializadas em hambúrgueres e dogs. Não oferece escolha de ponto. O banco remove as opções de ponto também de produtos novos/editados, preservando preços, imagens e descrições próprias.

Nos pastéis, o cliente marca tomate, milho, batata palha, ketchup e maionese. As escolhas não alteram o preço do pastel. Quando nenhuma é marcada, a cozinha recebe “Sem acompanhamentos”.

Mini coxinhas exigem exatamente uma escolha: um sabor disponível ou “Mistas / misturadas”. Inicialmente há Frango e Presunto. No admin → Produtos, a seção “Mini coxinhas: sabores disponíveis hoje” permite marcar disponibilidade, alterar nomes e cadastrar até seis sabores com justificativa. A opção mista é automática quando há pelo menos dois sabores e significa mistura dos sabores disponíveis, sem promessa de proporção fixa. Com um sabor, a mistura desaparece. Com nenhum, todas as porções ficam ocultas. A configuração permanece até a próxima edição; não há reinício automático diário.

A disponibilidade afeta novos pedidos e novas solicitações de alteração. Pedidos já criados mantêm o registro original. Um carrinho antigo com sabor/adicional indisponível é rejeitado no servidor e deve ser corrigido pelo cliente.

## Publicação

- Migração incremental: `supabase/migrations/20261110122940_menu_customizations.sql`. Não executar instaladores de banco vazio em produção.
- Publicar `customer-api` (mensagens de validação), `customer-assistant` e `integration-worker` (catálogo das sugestões, que não oferece adicionais avulsos), e o frontend desta versão. Preservar as configurações atuais de abertura, taxa, WhatsApp e pagamentos.
- Coordenar a migração e a publicação: a migração torna obrigatória a escolha de sabor nas mini coxinhas, e o frontend novo precisa receber essas opções. Antes de concluir, confirmar que todas as partes estão atualizadas. O checkout novo recusa cotações de adicionais de uma versão antiga do banco, evitando confirmar um total sem contabilizá-los.
- Homologar um hambúrguer/dog com adicionais, dois lanches iguais, um pastel com e sem acompanhamentos, mini coxinhas de cada sabor e mistas, indisponibilidade de um/todos os sabores, edição do carrinho e solicitação à cozinha. Conferir itens e valores na comanda real quando a impressora estiver instalada.

## Validação

`npm run validate` verifica o frontend e os helpers de associação/preço. `supabase/tests/menu_customizations.sql` roda apenas no banco descartável do CI, cobrindo preços, adicionais duplicados/fora de categoria, estoque idempotente, impressão, ponto rejeitado, acompanhamentos, disponibilidade, sabores e autorização do admin. A suíte não cria pedidos reais, cobra pagamentos nem dispara mensagens.
