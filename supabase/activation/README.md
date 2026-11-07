# Ativação do frontend atual

Este diretório usa exclusivamente o contrato em inglês de `supabase/migrations/`.
Não misturar com `supabase/sql_editor/` ou funções `eco-*`.

1. Confira o projeto no painel Supabase e execute `00_diagnostico.sql`.
2. **Somente em projeto novo e vazio**, execute o conteúdo completo de
   `01_instalacao_nova.sql` no SQL Editor. Ele instala 001–018 e o seed numa
   única transação, recusa estruturas/contas/buckets existentes e deixa os
   pedidos online e a entrega pausados.
3. Execute `00_diagnostico.sql` novamente e confira os indicadores. Depois
   crie a conta no Auth e ative somente o UUID correto como administrador,
   conforme [ativação](../../docs/activation.md).

Em projeto existente, não execute o instalador e não remova sua verificação.
Use somente as migrações faltantes depois de conferir os dados e o histórico.
Instalar pelo SQL Editor não registra automaticamente o histórico da CLI;
reconcilie esse histórico antes de usar `db push` futuramente.

Existe uma terceira estrutura antiga com `profiles.full_name`, `pin_code`,
`products.price` e `technical_sheets`; ela não é identificada somente pelos
indicadores `name`/`nome`. O diagnóstico inclui `contrato_legado` e a lista de
tabelas para evitar classificar esse projeto como vazio.

`02_preservar_legado_vazio.sql` é uma transição específica para as oito tabelas
desse legado, **todas sem registros**, sem usuários, buckets ou gatilhos Auth.
Depois de revisar a estrutura e as dependências, ele move as tabelas e as quatro
funções de negócio para um schema privado de preservação, mantendo dependências
e recusando qualquer dado existente. Não apaga objetos nem serve como migração
de dados. Só então o projeto pode receber o instalador 01. Não executar 02 em
outra estrutura ou num sistema em operação. Testes descartáveis verificam recusa
quando há dados e preservação dos objetos antes da instalação do contrato atual.

O arquivo de instalação é gerado das fontes existentes, com hash por origem:

```sh
npm run activation:prepare
npm run activation:check
```

Esses dois comandos apenas escrevem/conferem um arquivo local. Não conectam a
nenhum banco, não criam usuários e não publicam funções. Nunca executar
`supabase/tests/bootstrap.sql` no projeto hospedado.
