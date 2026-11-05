"""Portal LGPD independente com API MOCK; não acessa nenhum projeto ou cliente real."""
import json
import os
from pathlib import Path
import shutil
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1] / 'supabase/sql_editor/portal'
TOKEN = 'a' * 64  # Fixture pública, sem validade em qualquer backend real.

class StaticHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        if self.path == '/':
            body = (ROOT / 'index.html').read_text().replace('SEU-PROJETO.supabase.co', 'fixture.supabase.co').encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()

    def log_message(self, *_args):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), StaticHandler)
Thread(target=server.serve_forever, daemon=True).start()
origin = f'http://127.0.0.1:{server.server_port}'
requests = []

def mock_api(route):
    headers = {'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'content-type'}
    if route.request.method == 'OPTIONS':
        route.fulfill(status=204, headers=headers)
        return
    assert 'authorization' not in route.request.headers
    assert 'token=' not in route.request.url
    body = route.request.post_data_json
    assert body['token'] == TOKEN
    requests.append(body)
    data = {'protocolo': 'teste-123', 'status': 'concluido'} if body['acao'] == 'anonimizacao' else {'perfil': {'nome': 'Cliente fictício'}}
    route.fulfill(status=200, content_type='application/json', body=json.dumps(data), headers=headers)

try:
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium'), headless=True, args=['--no-sandbox'])
        context = browser.new_context(viewport={'width': 390, 'height': 844})
        context.route('https://fixture.supabase.co/**', mock_api)
        page = context.new_page()
        page.goto(origin)
        expect(page.locator('#export')).to_be_disabled()
        page.goto('about:blank')  # Link aberto numa navegação nova, como vindo do WhatsApp.
        page.goto(f'{origin}/#token={TOKEN}')
        expect(page.locator('#export')).to_be_enabled()
        assert page.url == origin + '/'
        assert page.evaluate('localStorage.length') == 0
        assert context.cookies() == []
        expect(page.locator('#forget')).to_be_disabled()
        with page.expect_download() as download:
            page.locator('#export').click()
        assert download.value.suggested_filename == 'meus-dados-planeta-lanches.json'
        expect(page.locator('#status')).to_contain_text('Relatório gerado')
        page.locator('#confirm-forget').check()
        expect(page.locator('#forget')).to_be_enabled()
        page.locator('#forget').click()
        expect(page.locator('#status')).to_contain_text('apagados')
        expect(page.locator('#status')).to_contain_text('teste-123')
        expect(page.locator('#export')).to_be_disabled()
        assert [r['acao'] for r in requests] == ['acesso', 'anonimizacao']
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
        page.screenshot(path='/tmp/planeta-privacy-portal-mobile.png', full_page=True)
        browser.close()
    print('Portal LGPD: token, isolamento, download e exclusão passaram (API simulada).')
finally:
    server.shutdown()
    server.server_close()
