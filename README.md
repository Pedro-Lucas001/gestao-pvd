# Planeta Lanches · Gestão

Painel web responsivo em React com a identidade preto, roxo e dourado da marca, cardápio da loja, pedidos e cozinha, conectado ao servidor Python/SQLite com login individual.

## Iniciar

Requer Node.js 22.12+ (ou 20.19+) e Python 3.10+.

```bash
npm ci
npm run build
python3 server.py
```

O servidor atende na porta 3000 e serve o frontend compilado em `dist/`. No primeiro acesso, cadastre o administrador em ambiente privado antes de disponibilizar o sistema. Não existe senha padrão. Para desenvolver a interface, mantenha o servidor Python ativo e execute `npm run dev` em outro terminal: o Vite encaminha `/api` para a porta 3000. O navegador usa rotas relativas, inclusive no celular, e não um endereço localhost fixo.

Depois de mudar o frontend ou cardápio, execute `npm run build` novamente. A inicialização informa quando o frontend ainda não foi compilado; a interface anterior foi substituída pela aplicação React.

## Cardápio e identidade visual

Os 47 produtos em `src/data/menu.json` foram transcritos do cardápio fornecido pela loja: hambúrgueres, dogões, porções, pastéis, mini coxinhas, bebidas e adicionais. Valores são inteiros em centavos. As bebidas **Santa Joana 200 ml (R$ 2)** e **Antarctica 200 ml (R$ 3)** foram confirmadas pelo responsável. As quantidades de mini coxinhas são opções de porção, não unidades avulsas.

O cardápio tem filtros por categoria e busca por nome ou ingrediente. A criação de pedidos usa o mesmo catálogo, com quantidades e adicionais como itens separados. Nas observações, informe a qual lanche pertence cada adicional. Nesta versão, alterar o catálogo exige editar o JSON e recompilar; não há cadastro persistente de produtos pela interface.

A imagem em `public/brand/planeta-art.png` é uma adaptação ilustrada gerada a partir da identidade enviada pela loja, para uso no painel. Não é o arquivo original da logo. As miniaturas das categorias são ícones ilustrativos; não são fotografias dos produtos. O símbolo compacto do planeta e o favicon acompanham as cores da marca.

## Acessos e operação

- **Administrador:** visão geral, cardápio, pedidos, cozinha, pagamentos manuais, equipe e estado das integrações.
- **Funcionário:** cadastro e consulta de pedidos e acompanhamento da cozinha, sem acesso à gestão da equipe e sem confirmação de pagamentos.

Pedidos ficam aguardando pagamento até a confirmação manual pelo administrador. Só então entram na cozinha e avançam por **Na fila → Em preparo → Pronto → Concluído**. A atualização ocorre a cada 15 segundos. O servidor valida permissões, sessões e proteção CSRF. Os dados ficam em `.data/planeta.db`, ignorado pelo Git. Mais detalhes sobre sessões, backups e configuração em [README.gestao.md](README.gestao.md).

O frontend React agora utiliza as rotas reais de autenticação, pedidos e equipe do servidor Python. As antigas telas de caixa e cadastro de produtos dependiam de rotas que não existiam nesse servidor; não são apresentadas como funcionalidades operacionais. Recebimentos confirmados aparecem na visão geral, sem simular um controle completo de caixa.

**Ainda não integrados:** Pix automático, recebimento de mensagens WhatsApp e impressão automática. O canal WhatsApp identifica pedidos digitados manualmente pela equipe. Cancelar um pedido não realiza estorno.

## Validar

```bash
npm run lint
npm run build
python3 -m unittest discover -s tests -v
```

Os testes do servidor usam banco temporário e verificam os perfis, a revogação de sessões, CSRF e o fluxo de pagamento/preparo. Os testes do catálogo verificam os valores e quantidades do cardápio e as bebidas confirmadas. Consulte [tests/README.md](tests/README.md) para a validação opcional no navegador.
