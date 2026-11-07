# Administração: produtos, imagens, estoque e resultados

A migração `202611070018_admin_control.sql` depende das migrações 001–017. Valide em homologação antes de aplicar no projeto real. O frontend e a função `staff-admin` precisam ser publicados junto com esta migração.

## Produtos e fotos

Em **Catálogo e preços**, use **Adicionar produto** ou **Editar**. Informe nome, preço, categoria, setor de preparo, descrição, personalizações e disponibilidade. Envie uma foto JPG, PNG ou WebP de até 5 MB e salve. O navegador prepara WebP com até 1600 px; o armazenamento aceita somente WebP, sem permitir sobrescrever URLs antigas. Somente admin pode enviar fotos. As fotos de produtos são públicas para o cardápio; não envie documentos ou imagens privadas.

O bucket dedicado `planeta-product-images` é criado público sem mudar outros buckets. Se já existir com uma configuração incompatível, a migração aborta para conferência. A URL salva no produto é um caminho do próprio bucket, e as telas resolvem a origem do Supabase configurado. URLs externas e imagens de outros buckets são rejeitadas. Fotos em uso não podem ser apagadas. Objetos enviados em edições canceladas podem ficar sem referência; admin pode removê-los pelo Storage quando não estiverem associados a produtos. Em domínio Supabase customizado, adicione a origem HTTPS exata ao `img-src` e ao `connect-src` da CSP.

Novos produtos disponíveis aparecem nas próximas consultas ao cardápio/caixa. O cardápio público atualiza automaticamente a cada minuto. Preços de pedidos enviados permanecem nos snapshots da venda. Configure a ficha técnica em **Estoque e fichas** antes de vender para obter baixa e custo completos.

## Estoque e resultado

**Visão geral** reúne recebimentos de balcão, links antigos e pedidos novos do site. Os botões **Dia**, **Semana** e **Mês** usam o horário de Recife. Semana vai de segunda-feira até a data de referência; mês vai do primeiro dia até essa data. A data pode consultar o histórico disponível dos últimos cinco anos.

Recebimentos são somados pela confirmação de cada pagamento, incluindo Pix complementares. Devoluções saem pela data de confirmação/registro da devolução. Insumos entram pelo custo capturado na baixa e despesas pela data cadastrada. O resultado operacional estimado é recebimento menos devoluções, custos registrados e despesas. Pedidos sem pagamento não viram receita. Dinheiro aceito para preparo permanece a receber até a conferência física. Custos de preparo de pedidos a receber podem ocorrer antes do recebimento.

Várias cobranças do mesmo pedido não duplicam a contagem de pedidos. Um pagamento depois estornado continua no recebimento original e aparece também na devolução, sem desaparecer do histórico. Taxas de provedor, impostos e despesas não cadastradas não estão incluídos: não é lucro contábil definitivo.

A cobertura das fichas passa a ser capturada no preparo. Vendas anteriores sem comprovação ou vendas novas sem ficha não exibem resultado: o dashboard mostra **Custos incompletos**. Adicionar uma ficha depois não inventa custos retroativos. Custos futuros do PDV preservam frações de centavo por grama/ml; registros antigos que já foram arredondados não podem recuperar a precisão perdida.

O estoque mostra saldos atuais por unidade, alertas no mínimo/abaixo dele, saldos negativos e valor estimado do saldo positivo pelo custo atual. Não soma gramas, unidades e mililitros como uma quantidade única. **Estoque e fichas** permite cadastrar insumos, custos, mínimos, entradas/perdas/correções auditadas e receitas com regras de modificadores. **DRE gerencial** usa dados reais e permite registrar despesas; as telas com valores de demonstração foram substituídas.

## Equipe e PIN

Em **Equipe e acessos**, crie uma conta individual com nome, e-mail, senha inicial e PIN exclusivo de quatro dígitos para o funcionário. Escolha caixa/atendimento ou cozinha e seu setor. O admin usa e-mail e senha. Compartilhe as credenciais somente com a pessoa responsável.

Caixa e cozinha entram em `/funcionario`, a mesma página inicial da equipe. Cada função encontra os módulos permitidos; cozinha continua sem finanças, cadastro de equipe ou catálogo administrativo. O terminal precisa estar cadastrado para entrada por PIN. O PIN fica como hash, não é exibido ao admin e não pode repetir o de outro funcionário ativo.

Na lista da equipe, admin pode bloquear/ativar, mudar função/setor ou definir outro PIN. A alteração e o PIN são confirmados em uma única transação: falha de PIN não deixa uma ativação ou troca de função parcial. Bloqueio/troca preservam as revogações de sessão existentes. A criação de usuário no Auth ocorre antes dessa transação; se a ativação falhar, a conta permanece inativa e deve ser concluída na lista, sem criar outra conta.

## Validação

`npm run validate`, testes PostgreSQL descartáveis incluindo `supabase/tests/admin_control.sql`, Deno check e testes puros. A suíte cobre imagens e permissões, PIN duplicado com rollback de função/ativação, custos fracionários, balcão mais cobranças complementares do site, devoluções, virada do dia de Recife, limites da semana/mês e ausência de lucro fictício quando faltam custos. Upload real no Storage e criação de usuários devem ser homologados em um projeto de testes; não use os fixtures SQL em produção.
