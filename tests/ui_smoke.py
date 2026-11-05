"""Optional browser validation. Requires playwright and a local Chromium."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='planeta-ui-') as temp:
    # Let the operating system select an available port before starting the child.
    import socket
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    process = subprocess.Popen(['python3', str(ROOT / 'server.py')], env={**os.environ, 'PORT':str(port), 'PLANETA_DB':str(Path(temp)/'ui.db')}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium'), headless=True, args=['--no-sandbox'])
            page = browser.new_page(viewport={'width':1440,'height':1080})
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.on('response', lambda response: errors.append(f'HTTP {response.status} {response.url}') if response.status>=500 else None)
            for attempt in range(50):
                try:
                    page.goto(f'http://127.0.0.1:{port}')
                    break
                except Exception:
                    if process.poll() is not None:
                        raise RuntimeError('Servidor não iniciou; execute npm run build.')
                    time.sleep(.1)
            page.get_by_label('Seu nome',exact=True).fill('Pedro')
            page.get_by_label('Usuário',exact=True).fill('admin')
            page.get_by_label('Senha',exact=True).fill('temporary-test-admin')
            page.get_by_role('button',name='Criar meu acesso').click()
            expect(page.get_by_role('heading',name='Olá, Pedro. Vamos nessa?')).to_be_visible()
            page.get_by_role('button',name='Cardápio',exact=True).click()
            expect(page.locator('.product-card')).to_have_count(47)
            page.screenshot(path='/tmp/planeta-cardapio-desktop.png',full_page=False)
            page.get_by_role('group',name='Categorias do cardápio').get_by_role('button',name='Mini coxinhas',exact=False).click()
            expect(page.locator('.product-card')).to_have_count(10)
            expect(page.get_by_role('heading',name='Mini coxinhas · 125 unidades')).to_be_visible()
            page.get_by_role('group',name='Categorias do cardápio').get_by_role('button',name='Bebidas',exact=False).click()
            expect(page.locator('.product-card')).to_have_count(12)
            page.get_by_label('Buscar no cardápio').fill('santa joana 200')
            expect(page.locator('.product-card')).to_have_count(1)
            expect(page.locator('.product-bottom strong')).to_have_text('R$\xa02,00')
            page.get_by_label('Buscar no cardápio').fill('produto inexistente')
            expect(page.get_by_role('heading',name='Nenhum sabor por aqui.')).to_be_visible()
            page.get_by_role('button',name='Limpar filtros').click()
            expect(page.locator('.product-card')).to_have_count(47)
            page.get_by_role('button',name='Adicionar X-Tudo ao pedido',exact=True).click()
            page.get_by_label('Cliente',exact=True).fill('Mesa 4')
            page.get_by_role('button',name='Aumentar X-Tudo',exact=True).click()
            page.get_by_role('button',name='Bacon R$ 3,00',exact=False).click()
            page.get_by_role('button',name='Santa Joana 200 ml R$ 2,00',exact=False).click()
            page.get_by_label('Observações').fill('Bacon no X-Tudo, sem cebola.')
            expect(page.locator('dialog .total-row strong')).to_have_text('R$\xa039,00')
            page.get_by_role('button',name='Criar pedido',exact=True).click()
            expect(page.locator('dialog')).not_to_be_visible()
            page.get_by_role('button',name='Pedidos',exact=False).first.click()
            expect(page.get_by_text('Mesa 4',exact=True)).to_be_visible()
            page.reload()
            expect(page.get_by_role('heading',name='Olá, Pedro. Vamos nessa?')).to_be_visible()
            page.get_by_role('button',name='Equipe e acessos',exact=True).click()
            page.get_by_role('button',name='Adicionar funcionário').click()
            page.get_by_label('Nome',exact=True).fill('Atendente')
            page.get_by_label('Usuário',exact=True).fill('atendente')
            page.get_by_label('Senha inicial',exact=True).fill('temporary-test-employee')
            page.get_by_role('button',name='Cadastrar funcionário').click()
            expect(page.get_by_text('Atendente',exact=True)).to_be_visible()
            page.get_by_role('button',name='Pedidos',exact=False).first.click()
            page.get_by_role('button',name='Abrir pedido 1',exact=True).click()
            page.get_by_role('button',name='Conferi o pagamento').click()
            expect(page.locator('dialog')).not_to_be_visible()
            page.get_by_role('button',name='Sair',exact=True).click()
            page.get_by_label('Usuário',exact=True).fill('atendente')
            page.get_by_label('Senha',exact=True).fill('temporary-test-employee')
            page.get_by_role('button',name='Entrar no painel').click()
            expect(page.get_by_role('heading',name='Cada pedido no seu lugar.')).to_be_visible()
            expect(page.get_by_role('button',name='Equipe e acessos',exact=True)).to_have_count(0)
            expect(page.get_by_role('button',name='Cardápio',exact=True)).to_have_count(0)
            page.get_by_role('button',name='Cozinha',exact=True).click()
            page.get_by_role('button',name='Iniciar preparo').click()
            expect(page.get_by_role('button',name='Marcar como pronto')).to_be_visible()
            page.get_by_role('button',name='Marcar como pronto').click()
            expect(page.get_by_role('button',name='Concluir pedido')).to_be_visible()
            page.get_by_role('button',name='Concluir pedido').click()
            expect(page.locator('.kitchen-card')).to_have_count(0)
            page.get_by_role('button',name='Sair',exact=True).click()
            page.get_by_label('Usuário',exact=True).fill('admin')
            page.get_by_label('Senha',exact=True).fill('temporary-test-admin')
            page.get_by_role('button',name='Entrar no painel').click()
            expect(page.get_by_role('heading',name='Olá, Pedro. Vamos nessa?')).to_be_visible()
            page.set_viewport_size({'width':390,'height':844})
            page.get_by_role('button',name='Abrir menu').click()
            page.get_by_role('button',name='Cardápio',exact=True).click()
            expect(page.locator('.product-card')).to_have_count(47)
            expect(page.locator('.sidebar')).not_to_be_visible()
            page.evaluate('window.scrollTo(0,0)')
            if page.get_by_role('button',name='Dispensar aviso').count():
                page.get_by_role('button',name='Dispensar aviso').click()
            assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth'), 'Overflow horizontal no celular'
            page.screenshot(path='/tmp/planeta-cardapio-mobile.png',full_page=False)
            assert page.locator('img').evaluate_all('(images) => images.every(i => i.complete && i.naturalWidth > 0)'), 'Imagem não carregou'
            assert not errors, errors
            browser.close()
            print('UI OK: 47 produtos, filtros, busca, bebidas, carrinho R$39, persistência, equipe, pagamento, cozinha, permissões e celular. Sem erros JavaScript.')
    finally:
        process.terminate()
        process.wait()
