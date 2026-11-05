"""UI touch/KDS com Auth, REST e protocolo WebSocket SIMULADOS; nenhum provedor real."""
import json
import os
import shutil
import signal
from datetime import datetime, timezone, timedelta
from urllib.parse import urlsplit, parse_qs
from playwright.sync_api import sync_playwright, expect
from ui_smoke import serve, navigate, mock_api, IDS, jwt, CATALOG

BASE = 'http://127.0.0.1:54399'
now = datetime.now(timezone.utc)
def ago(minutes):
    return (now - timedelta(minutes=minutes)).isoformat()
def ticket(key, sector, age, name, quantity=1):
    return {'id': key, 'order_number': 120, 'sector': sector, 'status': 'queued', 'created_at': ago(age),
            'started_at': None, 'items': [{'name': name, 'quantity': quantity, 'modifiers': ['Sem cebola'] if sector == 'grill' else [], 'notes': ''}]}
state = {'tickets': [ticket('grill-1', 'grill', 5, 'X-Tudo', 18), ticket('bar-1', 'bar', 12, 'Refrigerante', 3), ticket('fryer-1', 'fryer', 21, 'Batata frita', 4)], 'fails': 0, 'ticket_queries': 0}

class Realtime:
    def __init__(self):
        self.channels = []
        self.seq = 0
    def accept(self, socket):
        def message(raw):
            request = json.loads(raw)
            if isinstance(request, list):
                request = dict(zip(['join_ref','ref','topic','event','payload'],request))
            if request['event'] == 'phx_join':
                bindings = []
                for binding in request['payload']['config'].get('postgres_changes', []):
                    self.seq += 1
                    bindings.append({**binding, 'id': self.seq})
                self.channels.append((socket, request['topic'], bindings))
                socket.send(json.dumps([request.get('join_ref'),request['ref'],request['topic'],'phx_reply',{'status':'ok','response':{'postgres_changes':bindings}}]))
            elif request['event'] in ['heartbeat', 'phx_leave']:
                socket.send(json.dumps([request.get('join_ref'),request['ref'],request['topic'],'phx_reply',{'status':'ok','response':{}}]))
        socket.on_message(message)
    def emit(self, table, event='INSERT'):
        for socket, topic, bindings in list(self.channels):
            ids = [b['id'] for b in bindings if b['table'] == table]
            if not ids:
                continue
            socket.send(json.dumps([None,None,topic,'postgres_changes',{'ids': ids, 'data': {'schema': 'public', 'table': table, 'type': event,
                'commit_timestamp': datetime.now(timezone.utc).isoformat(), 'columns': [], 'record': {}, 'old_record': {}, 'errors': None}}]))

def api(route):
    path = urlsplit(route.request.url).path
    headers = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, x-client-info, content-type', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'}
    if route.request.method == 'OPTIONS':
        route.fulfill(status=204, headers=headers)
        return
    body = route.request.post_data_json if route.request.post_data else {}
    status = 200
    if path == '/functions/v1/fast-pass':
        if body.get('pin') not in ['1111','2222']:
            state['fails'] += 1
            status = 429 if state['fails'] >= 5 else 401
            data = {'error': 'PIN_LOCKED' if status == 429 else 'INVALID_PIN',
                    'retry_at': (datetime.now(timezone.utc)+timedelta(minutes=3)).isoformat() if status == 429 else None}
        else:
            role = 'cashier' if body['pin'] == '1111' else 'kitchen'
            assert body['terminal_token'] == 'f'*64
            data = {'session': {'access_token': jwt(role), 'refresh_token': 'fake-refresh-only', 'expires_at': int(datetime.now(timezone.utc).timestamp())+3600,
                    'expires_in': 3600, 'token_type': 'bearer'}, 'lease_expires_at': (datetime.now(timezone.utc)+timedelta(minutes=10)).isoformat()}
    elif path == '/rest/v1/products':
        data = [{**product, 'sector': 'bar' if product['category']=='bebidas' else 'grill' if product['category'] in ['hamburgueres','dogoes','adicionais'] else 'fryer'} for product in CATALOG]
    elif path == '/rest/v1/kitchen_tickets':
        state['ticket_queries'] += 1
        sector = parse_qs(urlsplit(route.request.url).query).get('sector', [''])[0]
        data = [t for t in state['tickets'] if t['status'] not in ['ready','cancelled'] and (not sector or sector == 'eq.'+t['sector'])]
    elif path == '/rest/v1/rpc/update_ticket':
        for t in state['tickets']:
            if t['id'] == body['p_ticket']:
                t['status'] = body['p_status']
        data = None
    elif path == '/rest/v1/rpc/kitchen_load_snapshot':
        data = []
        for sector in ['grill','fryer','bar']:
            rows = [t for t in state['tickets'] if t['sector'] == sector]
            data.append({'sector': sector, 'queued_items': sum(sum(i['quantity'] for i in t['items']) for t in rows if t['status'] == 'queued'),
                'preparing_items': sum(sum(i['quantity'] for i in t['items']) for t in rows if t['status'] == 'preparing'),
                'average_unit_seconds': 180, 'reference_unit_seconds': 180, 'parallel_capacity': 3, 'critical_items': 15, 'sample_count': 0})
    else:
        return mock_api(route)
    route.fulfill(status=status, content_type='application/json', body=json.dumps(data), headers=headers)

def enter_pin(page, value):
    for digit in value:
        page.get_by_role('button', name=f'Dígito {digit}', exact=True).click()
    page.get_by_role('button', name='Acessar com PIN', exact=True).click()

process, port = serve(True)
errors = []
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium'), headless=True, args=['--no-sandbox'])
        # Teclado touch, limpar/backspace, bloqueio e entrada direta no PDV.
        context = browser.new_context(viewport={'width': 390, 'height': 844})
        context.route(BASE+'/**', api)
        context.add_init_script("try{localStorage.setItem('planeta:registered-terminal:v1','"+'f'*64+"')}catch{}")
        page = context.new_page(); page.on('pageerror', lambda e: errors.append(str(e)))
        navigate(page, port)
        page.get_by_role('tab', name='Funcionário · PIN', exact=True).click()
        expect(page.get_by_role('button', name='Acessar com PIN')).to_be_disabled()
        page.get_by_role('button', name='Dígito 1', exact=True).click()
        page.get_by_role('button', name='Apagar último dígito').click()
        expect(page.get_by_label('PIN de 4 dígitos')).to_have_value('')
        assert page.get_by_role('button', name='Dígito 1', exact=True).bounding_box()['height'] >= 60
        for attempt in range(5):
            enter_pin(page, '0000')
            expect(page.get_by_role('alert')).to_be_visible()
        expect(page.get_by_role('button', name='Acessar com PIN')).to_be_disabled()
        expect(page.locator('.pin-countdown')).to_contain_text('Aguarde')
        page.screenshot(path='/tmp/planeta-fastpass-mobile.png', full_page=True)
        context.close()
        state['fails'] = 0  # Novo cenário isolado do mock; expiração real é testada no PostgreSQL.
        # Nova sessão legítima em outro contexto: papel vem do Auth/servidor, não do PIN local.
        context = browser.new_context(viewport={'width': 1440, 'height': 1000})
        context.route(BASE+'/**', api)
        context.add_init_script("try{localStorage.setItem('planeta:registered-terminal:v1','"+'f'*64+"')}catch{}")
        page = context.new_page(); page.on('pageerror', lambda e: errors.append(str(e)))
        navigate(page, port)
        page.get_by_role('tab', name='Funcionário · PIN', exact=True).click()
        enter_pin(page, '1111')
        expect(page).to_have_url(f'http://127.0.0.1:{port}/pdv')
        expect(page.locator('.sidebar')).to_have_count(0)
        expect(page.get_by_label('Tela bloqueada')).to_have_count(0)
        expect(page.get_by_role('button', name='Abrir meu caixa')).to_be_visible()
        page.get_by_role('button', name='Abrir meu caixa').click()
        page.get_by_role('button', name='Adicionar X-Tudo', exact=True).click()
        page.get_by_role('button', name='Adicionar X-Tudo', exact=True).click()
        expect(page.locator('.draft-preparation')).to_contain_text('20 min')
        expect(page.locator('[data-station="grill"]')).to_contain_text('Alta demanda')
        context.close()
        # Admin: WebSocket simulado, filtros e entrada de cartão sem esperar polling de 10s.
        realtime = Realtime()
        context = browser.new_context(viewport={'width': 1440, 'height': 1080})
        context.route(BASE+'/**', api)
        context.route_web_socket('ws://127.0.0.1:54399/realtime/**', realtime.accept)
        page = context.new_page(); page.clock.install(); page.on('pageerror', lambda e: errors.append(str(e)))
        navigate(page, port)
        page.get_by_label('E-mail', exact=True).fill('admin@fixture.test')
        page.get_by_label('Senha', exact=True).fill('test-password-only')
        page.get_by_role('button', name='Entrar no meu espaço').click()
        expect(page).to_have_url(f'http://127.0.0.1:{port}/dashboard')
        expect(page.get_by_role('link', name='DRE gerencial')).to_be_visible()
        page.evaluate("window.tacticalDocumentMarker = 'same-document'")
        page.get_by_role('link', name='Cozinha · KDS').click()
        expect(page.get_by_text('Realtime conectado', exact=True)).to_be_visible()
        expect(page.locator('.kds-card')).to_have_count(3)
        expect(page.locator('[data-ticket="grill-1"]')).to_have_class('kds-card normal')
        expect(page.locator('[data-ticket="bar-1"]')).to_have_class('kds-card warning')
        expect(page.locator('[data-ticket="fryer-1"]')).to_have_class('kds-card critical')
        expect(page.locator('[data-station="grill"]')).to_contain_text('Alta demanda')
        page.get_by_role('tab', name='Bebidas').click()
        expect(page.locator('.kds-card')).to_have_count(1)
        expect(page.locator('.kds-card')).to_contain_text('Refrigerante')
        expect(page.locator('.kds-card')).not_to_contain_text('X-Tudo')
        page.get_by_role('tab', name='Todas as praças').click()
        # Novo ticket 9m59s para provar também a troca automática de cor pelo relógio.
        fresh = ticket('grill-2','grill',9.99,'X-Bacon',2)
        fresh['created_at'] = (datetime.now(timezone.utc)-timedelta(minutes=9,seconds=55)).isoformat()
        state['tickets'].append(fresh)
        queries = state['ticket_queries']
        realtime.emit('kitchen_tickets')
        expect(page.locator('[data-ticket="grill-2"]')).to_be_visible(timeout=3000)
        assert state['ticket_queries'] > queries
        expect(page.locator('[data-ticket="grill-2"]')).to_have_class('kds-card normal')
        page.clock.fast_forward(6000)
        expect(page.locator('[data-ticket="grill-2"]')).to_have_class('kds-card warning')
        realtime.emit('kitchen_station_load')
        expect(page.locator('[data-station="grill"] .station-load-count > strong')).to_have_text('20')
        page.evaluate('window.scrollTo(0,0)')
        page.screenshot(path='/tmp/planeta-kds-tactical-desktop.png', full_page=True)
        # Novos efeitos só movem cartões com animação; o documento continua o mesmo.
        assert page.evaluate('window.tacticalDocumentMarker') == 'same-document'
        page.set_viewport_size({'width': 390, 'height': 844})
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
        page.screenshot(path='/tmp/planeta-kds-tactical-mobile.png', full_page=True)
        context.close()
        # PIN da cozinha leva exclusivamente ao setor configurado.
        context = browser.new_context(viewport={'width': 1280, 'height': 900})
        context.route(BASE+'/**', api)
        context.add_init_script("try{localStorage.setItem('planeta:registered-terminal:v1','"+'f'*64+"')}catch{}")
        page = context.new_page(); page.on('pageerror', lambda e: errors.append(str(e)))
        navigate(page, port)
        page.get_by_role('tab', name='Funcionário · PIN', exact=True).click()
        enter_pin(page, '2222')
        expect(page).to_have_url(f'http://127.0.0.1:{port}/cozinha')
        expect(page.locator('.sidebar')).to_have_count(0)
        expect(page.get_by_role('tab', name='Bebidas')).to_be_disabled()
        expect(page.locator('.kds-card')).to_have_count(2)
        expect(page.locator('.kds-grid')).not_to_contain_text('Refrigerante')
        page.set_viewport_size({'width':390,'height':844})
        expect(page.locator('.staff-identity > span')).to_be_visible()
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
        page.screenshot(path='/tmp/planeta-kds-staff-mobile.png',full_page=True)
        context.close()
        assert not errors, errors
        browser.close()
    print('TACTICAL UI OK: numpad touch, lockout, Fast-Pass por função, menu admin isolado, filtros, cores, carga e eventos WebSocket simulados.')
finally:
    os.killpg(process.pid, signal.SIGTERM)
    process.wait()
