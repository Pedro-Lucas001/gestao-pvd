"""Browser tests: explicit visual preview + SIMULATED Supabase HTTP.
These verify UI/route/retry behavior, NOT hosted Auth/Realtime/gateway readiness.
Run `python3 tests/ui_smoke.py` with Playwright Python and Chromium installed.
"""
import base64
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
from datetime import datetime,timezone,timedelta
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright, expect

ROOT=Path(__file__).resolve().parents[1]
SOURCE=json.loads((ROOT/'src/data/menu.json').read_text())
CATALOG=[{**p,'price_cents':p['price'],'image_path':f"/menu/{p['category']}.svg",'allowed_modifiers':['Sem cebola','Ponto: ao ponto','Ponto: bem passado'] if p['category']=='hamburgueres' else []} for p in SOURCE]
IDS={'admin':'00000000-0000-0000-0000-000000000001','cashier':'00000000-0000-0000-0000-000000000002','kitchen':'00000000-0000-0000-0000-000000000004'}
def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1',0))
        return s.getsockname()[1]
def b64(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip('=')
def jwt(role):
    return b64({'alg':'HS256','typ':'JWT'})+'.'+b64({'sub':IDS[role],'aud':'authenticated','role':'authenticated','session_id':'ui-fixture','exp':int(time.time())+3600})+'.test-signature-only'
def serve(configured):
    number=port()
    proc=subprocess.Popen(['npm','run','dev','--','--host','127.0.0.1','--port',str(number),'--strictPort'],cwd=ROOT,env={**os.environ,'VITE_SUPABASE_URL':'http://127.0.0.1:54399' if configured else '', 'VITE_SUPABASE_PUBLISHABLE_KEY':'sb_publishable_ui_test' if configured else ''},stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
    return proc,number

def navigate(page,number):
    for attempt in range(50):
        try:
            page.goto(f'http://127.0.0.1:{number}')
            return
        except Exception:
            time.sleep(.1)
    raise RuntimeError('Vite não iniciou')

def mock_api(route):
    path=urlsplit(route.request.url).path
    headers=route.request.headers
    token=headers.get('authorization','').split(' ')[-1]
    role=next((r for r in IDS if token==jwt(r)),'cashier')
    # Compare sub instead of a time-sensitive signature generated again.
    try:
        payload=token.split('.')[1]
        sub=json.loads(base64.urlsafe_b64decode(payload+'='*(-len(payload)%4)))['sub']
        role=next(r for r in IDS if IDS[r]==sub)
    except Exception:
        pass
    body=route.request.post_data_json if route.request.post_data else {}
    status=200
    if path=='/auth/v1/token':
        role=body['email'].split('@')[0]
        data={'access_token':jwt(role),'refresh_token':'fake-refresh-for-ui-test','token_type':'bearer','expires_in':3600,'user':{'id':IDS[role],'aud':'authenticated','role':'authenticated','email':body['email'],'app_metadata':{},'user_metadata':{}}}
    elif path=='/auth/v1/logout':
        data={}
    elif path=='/rest/v1/rpc/operator_context':
        data={'id':IDS[role],'name':role.capitalize(),'role':role,'active':True,'requires_password':False,'sector':'grill' if role=='kitchen' else None}
    elif path=='/rest/v1/rpc/kitchen_load_snapshot':
        data=[{'sector':sector,'queued_items':0,'preparing_items':0,'average_unit_seconds':180,'reference_unit_seconds':180,'parallel_capacity':3,'critical_items':15,'sample_count':0} for sector in ['grill','fryer','bar']]
    elif path=='/rest/v1/rpc/admin_metrics':
        data={'revenue_cents':0,'paid_orders':0,'discounts_cents':0,'cancelled':0,'cancelled_credit_cents':0,'peaks':[],'margins':[],'bottlenecks':[],'low_stock':[]}
    elif path=='/auth/v1/user':
        data={'id':IDS[role],'aud':'authenticated','role':'authenticated','email':role+'@fixture.test','app_metadata':{},'user_metadata':{}}
    elif path=='/rest/v1/profiles':
        data={'id':IDS[role],'name':role.capitalize(),'role':role,'active':True,'sector':'grill' if role=='kitchen' else None}
    elif path=='/rest/v1/rpc/public_menu':
        data=[{k:product.get(k,'') for k in ['id','name','category','description','price_cents','image_path']} for product in CATALOG]
    elif path=='/rest/v1/products':
        data=CATALOG
    elif path=='/rest/v1/shifts':
        data=None
    elif path=='/rest/v1/rpc/unlock_terminal':
        data={'ok':True,'expires_at':(datetime.now(timezone.utc)+timedelta(hours=1)).isoformat()}
    elif path=='/rest/v1/rpc/heartbeat_terminal':
        data={'ok':True,'expires_at':(datetime.now(timezone.utc)+timedelta(hours=1)).isoformat()}
    elif path=='/rest/v1/rpc/lock_terminal':
        data=None
    elif path=='/rest/v1/ingredients':
        data=[]
    elif path=='/rest/v1/recipe_items':
        data=[]
    elif path=='/rest/v1/recipe_modifier_rules':
        data=[]
    elif path=='/rest/v1/rpc/checkout_menu':
        data={'label':'Delivery de teste','channel':'delivery','products':CATALOG}
    elif path=='/rest/v1/rpc/checkout_order':
        mock_api.public_request=body
        data={'id':'public-fixture','number':99,'total_cents':700,'status':'pending_payment'}
    elif path=='/rest/v1/rpc/checkout_status':
        data={'id':'public-fixture','number':99,'total_cents':700,'status':'pending_payment','fulfillment_state':'waiting','pix':None}
    elif path=='/functions/v1/checkout-payment':
        status=503;data={'error':'Pix ainda não configurado pela loja.'}
    elif path=='/rest/v1/rpc/open_shift':
        mock_api.shift=True
        data='shift-fixture'
    elif path=='/rest/v1/rpc/create_order':
        mock_api.requests.append(body)
        if len(mock_api.requests)==1:
            status=502
            data={'message':'SIMULATED_RESPONSE_LOST','code':''}
        else:
            data=[{'id':'order-fixture','number':1,'total_cents':1700,'status':'pending_payment'}]
    elif path=='/rest/v1/rpc/begin_payment':
        data={'id':body['p_key'],'amount_cents':1700,'method':'cash','status':'pending'}
    elif path=='/rest/v1/rpc/confirm_cash':
        data=None
    elif path=='/rest/v1/orders':
        data={'id':'order-fixture','status':'pending_payment','total_cents':1700}
    elif path=='/rest/v1/kitchen_tickets':
        data=[]
    else:
        status=400
        data={'message':'Unexpected UI fixture request '+path}
    if path=='/rest/v1/shifts' and mock_api.shift:
        data={'id':'shift-fixture','opened_at':'2026-11-05T18:00:00Z','opening_cents':0}
    route.fulfill(status=status,content_type='application/json',body=json.dumps(data),headers={'Access-Control-Allow-Origin':'*'})
mock_api.shift=False
mock_api.requests=[]

if __name__=='__main__':
    import signal
    processes=[]
    try:
        with sync_playwright() as p:
            browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium'),headless=True,args=['--no-sandbox'])
            preview,preview_port=serve(False);processes.append(preview)
            page=browser.new_page(viewport={'width':1440,'height':1080})
            errors=[]
            page.on('pageerror',lambda e:errors.append(str(e)))
            navigate(page,preview_port)
            expect(page.get_by_role('heading',name='Nosso cardápio.',exact=True)).to_be_visible()
            expect(page.locator('[data-menu-product]')).to_have_count(47)
            expect(page.locator('.sidebar')).to_have_count(0)
            expect(page.get_by_role('button',name='Cobrar e Enviar (KDS)')).to_have_count(0)
            page.get_by_role('searchbox',name='Buscar no cardápio').fill('x-tudo')
            expect(page.locator('[data-menu-product]')).to_have_count(1)
            page.get_by_role('button',name='Limpar busca',exact=True).click()
            page.get_by_role('button',name='Pastéis',exact=True).click()
            expect(page.locator('[data-menu-product]')).to_have_count(3)
            page.screenshot(path='/tmp/planeta-cardapio-desktop.png',full_page=False)
            page.set_viewport_size({'width':390,'height':844})
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
            page.screenshot(path='/tmp/planeta-cardapio-mobile.png',full_page=False)
            page.get_by_role('link',name='Área da equipe',exact=True).click()
            expect(page.get_by_role('heading',name='Vamos começar o turno?',exact=True)).to_be_visible()
            page.goto(f'http://127.0.0.1:{preview_port}/pdv')
            expect(page).to_have_url(f'http://127.0.0.1:{preview_port}/login')
            page.close()
            app,app_port=serve(True);processes.append(app)
            for role in ['cashier','kitchen','admin']:
                context=browser.new_context(viewport={'width':1440,'height':1080})
                context.route('http://127.0.0.1:54399/**',mock_api)
                page=context.new_page();page.add_init_script("try{localStorage.setItem('planeta:registered-terminal:v1','"+'f'*64+"')}catch{}");page.clock.install();page.on('pageerror',lambda e:errors.append(str(e)))
                navigate(page,app_port)
                page.goto(f'http://127.0.0.1:{app_port}/login')
                page.get_by_label('E-mail',exact=True).fill(role+'@fixture.test')
                page.get_by_label('Senha',exact=True).fill('test-password-only')
                page.get_by_role('button',name='Entrar no meu espaço').click()
                if role in ['cashier','kitchen']:
                    page.get_by_label('PIN de 4 dígitos').fill('1234')
                    page.get_by_role('button',name='Destravar terminal').click()
                if role=='cashier':
                    page.get_by_role('button',name='Abrir meu caixa').click()
                    expect(page.locator('[data-product-card]')).to_have_count(47)
                    page.get_by_role('button',name='Adicionar X-Tudo',exact=True).click()
                    context.set_offline(True)
                    expect(page.get_by_role('button',name='Cobrar e Enviar (KDS)')).to_be_disabled()
                    expect(page.get_by_text('Sem internet. O rascunho está preservado neste terminal.',exact=False)).to_be_visible()
                    context.set_offline(False)
                    page.get_by_role('button',name='Cobrar e Enviar (KDS)').click()
                    page.get_by_role('button',name='Reenviar mesma tentativa').click()
                    expect(page.get_by_role('button',name='Confirmar recebimento em dinheiro')).to_be_visible()
                    assert len(mock_api.requests)==2 and mock_api.requests[0]==mock_api.requests[1], 'Retry changed body/key'
                    page.get_by_role('button',name='Confirmar recebimento em dinheiro').click()
                    expect(page.get_by_role('heading',name='Pagamento confirmado.')).to_be_visible()
                    page.clock.fast_forward(600001)
                    expect(page.get_by_label('Tela bloqueada')).to_be_visible()
                    expect(page.get_by_label('Nome do cliente')).to_have_count(0)
                    page.screenshot(path='/tmp/planeta-idle-lock.png',full_page=False)
                    page.get_by_label('PIN de 4 dígitos').fill('1234')
                    page.get_by_role('button',name='Destravar terminal').click()
                    expect(page.get_by_role('heading',name='Pagamento confirmado.')).to_be_visible()
                if role in ['cashier','kitchen']:
                    expect(page.locator('.sidebar')).to_have_count(0)
                    for path in ['/dashboard','/estoque','/relatorios','/equipe']:
                        page.goto(f'http://127.0.0.1:{app_port}'+path)
                        expect(page.get_by_role('heading',name='Esta área tem outro destino.')).to_be_visible()
                        assert '/acesso-negado' in page.url
                else:
                    page.goto(f'http://127.0.0.1:{app_port}/estoque')
                    expect(page.get_by_role('heading',name='Cada insumo sob controle.')).to_be_visible()
                    page.clock.fast_forward(600001)
                    expect(page.get_by_label('Tela bloqueada')).to_be_visible()
                    page.reload()
                    expect(page.get_by_label('Tela bloqueada')).to_be_visible()
                    page.get_by_label('PIN de 4 dígitos').fill('1234')
                    page.get_by_role('button',name='Destravar terminal').click()
                    expect(page.get_by_role('heading',name='Cada insumo sob controle.')).to_be_visible()
                context.close()
            public=browser.new_context()
            public.route('http://127.0.0.1:54399/**',mock_api)
            page=public.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
            page.goto(f'http://127.0.0.1:{app_port}/pedido?token='+('a'*64))
            page.get_by_role('button',name='Adicionar Simples',exact=True).click()
            page.get_by_label('Nome',exact=True).fill('Cliente de teste')
            page.get_by_label('Telefone com DDD',exact=True).fill('5581999999999')
            page.get_by_label('Endereço completo para entrega',exact=True).fill('Endereço de teste, número 10')
            page.get_by_role('button',name='Enviar pedido e seguir para pagamento').click()
            expect(page.get_by_role('heading',name='Aguardando pagamento',exact=True)).to_be_visible()
            assert mock_api.public_request['p_contact']['whatsapp_consent'] is False
            assert 'price_cents' not in mock_api.public_request['p_items'][0]
            page.get_by_role('button',name='Gerar Pix com valor exato').click()
            expect(page.get_by_text('Pix ainda não configurado pela loja.',exact=True)).to_be_visible()
            expect(page.get_by_role('heading',name='Aguardando pagamento',exact=True)).to_be_visible()
            public.close()
            assert not errors,errors
            browser.close()
            print('UI OK: cardápio público, 47 produtos, filtros, login interno, celular, offline, mesmo body/key no retry, pagamento dinheiro, auto-lock após 10 min e rotas por cargo. Auth/REST SIMULADOS; sem validação de Supabase hospedado.')
    finally:
        for proc in processes:
            os.killpg(proc.pid,signal.SIGTERM)
            proc.wait()
