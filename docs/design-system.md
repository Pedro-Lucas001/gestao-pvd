# Planeta Lanches — padrão oficial do PDV e KDS

O `PdvTemplate` fornecido pela loja é a referência visual destes dois módulos.

| Elemento | Padrão |
| --- | --- |
| Fundo principal | `#1a1a1a` |
| Cards e painéis | `#2d2d2d` |
| Destaques e ação primária | `#ff5722` |
| Hover de ação primária | `#e64a19` |
| Texto principal | Branco / `gray-100` |
| Texto secundário | `gray-400` |
| Cards e botão principal | `rounded-xl` — 12px |
| Campo, linha de comanda | `rounded-lg` — 8px |
| Categorias e imagem | `rounded-full` |
| Imagem do produto | Círculo de 96px, arquivo do catálogo; ícone Lucide se indisponível |
| Ícones | `lucide-react` |

O título/preço de exemplo e as seis repetições estáticas foram substituídos pelos produtos e preços reais do catálogo. Nenhum novo produto, valor ou pedido fictício foi inserido no banco.

## Código dos módulos

- `src/pdv/PDV.jsx`: controller funcional, com `useState`/`useEffect`, carregamento Supabase, pesquisa, categoria, adição/quantidade/remoção, personalizações, totais em centavos e persistência do rascunho por operador.
- `src/pdv/PdvTemplate.jsx`: composição visual do catálogo à esquerda e comanda de 384px à direita. A grade usa consultas de tamanho do contêiner para adaptar duas, três ou quatro colunas ao espaço disponível. No celular, a comanda fica abaixo e o catálogo tem rolagem limitada; o botão “Voltar ao cardápio” mantém o retorno acessível.
- `src/pdv/PaymentActions.jsx`: preserva a etapa de cobrança e os estados de envio/reenvio/pagamento. “Cobrar e Enviar (KDS)” abre a cobrança; **a cozinha só recebe após confirmação válida do pagamento**. Não existe confirmação Pix simulada.
- `src/kds/KDS.jsx`: conexão Realtime, reconciliação, filtros por praça, relógio e ações do setor. Mantém isolamento dos tickets no servidor.
- `src/kds/OrderTicketCard.jsx`: painel `#2d2d2d` estável, com borda esquerda de 4px: verde abaixo de 10 minutos, amarela entre 10 e 20, vermelha acima de 20. Texto e ícone de tempo complementam a cor. O botão usa o mesmo laranja, arredondamento e hover do PDV.
- `src/design/operational.js`: estilos compartilhados das ações, campos e controles.
- `src/design/operational.css`: integração Tailwind 4 e ajustes pontuais da cobrança existente.

O Tailwind utiliza o prefixo `pl:` e não carrega o preflight global, para não alterar por acidente as telas de autenticação e administração existentes. As utilidades são marcadas como importantes nessa importação e só são aplicadas quando o componente opta pelas classes `pl:`. As diretivas `prefix(pl)`/`important` dos imports são processadas pelo plugin oficial `@tailwindcss/vite`.

As funções administrativas adicionais estão em uma seção recolhível, e o indicador de carga/tempo de produção tem um resumo compacto. A comanda e o catálogo permanecem o foco do layout oficial. A previsão por praça continua disponível sem misturar dados financeiros ou contatos no KDS.

## Verificação

`npm run validate` verifica lint, lógica e build. `python3 tests/ui_smoke.py` verifica o carrinho, personalizações, recarga do rascunho, remoção, pagamento e responsividade; `python3 tests/tactical_ui_smoke.py` verifica filtros, atualizações por WebSocket simulado e urgência por tempo. Os testes de navegador também conferem as cores calculadas, raio de 12px e espessura da borda esquerda. Auth/REST/WebSocket são simulados nesses testes; nenhum pedido ou pagamento real é gerado.

Esta atualização é de frontend e não requer uma nova migração SQL. As dependências Tailwind estão no `package-lock.json`; use `npm ci` antes de compilar. Não houve publicação do ambiente.
