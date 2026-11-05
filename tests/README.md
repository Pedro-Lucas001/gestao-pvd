Os testes principais usam somente a biblioteca padrão do Python:

```sh
python3 -m unittest discover -s tests -v
```

Teste opcional de interface, em ambiente com Playwright Python e Chromium instalados:

```sh
npm run build
python3 tests/ui_smoke.py
```

O script usa banco temporário e porta independente. Não usa as contas ou os pedidos reais da loja. Verifica o catálogo, busca, categorias, preços das bebidas, seleção e quantidade dos produtos, persistência do pedido após recarregar, cadastro e login de funcionário, pagamento, cozinha, permissões, imagem da marca e layout de celular. `CHROMIUM_PATH` permite selecionar outro executável. Capturas são salvas em `/tmp/planeta-cardapio-desktop.png` e `/tmp/planeta-cardapio-mobile.png`.
