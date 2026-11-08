"""Local browser QA with a simulated customer API; no live payment or printing."""
import json, os, signal, socket, subprocess, time, re
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
ROOT=Path(__file__).resolve().parents[1]
PRODUCT={'product_id':'test-burger','name':'Burger teste','price_cents':1000,'allowed_modifiers':[],'category':'hamburgueres','description':'Teste','image_path':'/menu/hamburgueres.svg'}
ITEM={'product_id':'test-burger','name':'Burger teste','quantity':1,'unit_price_cents':1000,'modifiers':[],'notes':'','sector':'grill'}
state={'created':None,'status':'accepted'}
def mock(route):
    if route.request.method=='OPTIONS':
        route.fulfill(status=200,headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*'});return
    data=route.request.post_data_json or {}
    action=data.get('action')
    if action=='config':
        result={'enabled':True,'delivery_enabled':True,'delivery_fee_cents':100,'delivery_card_enabled':True,'cash_enabled':True,'whatsapp_number':'','payments':{'pix':True,'card':False,'manual_pix':True},'catalog':[PRODUCT]}
    elif action=='quote':
        base=1000+(100 if data['fulfillment']=='delivery' else 0)
        fee=(base*6+50)//100 if data.get('method')=='card_delivery' else 0
        result={'subtotal_cents':1000,'delivery_fee_cents':base-1000,'card_fee_cents':fee,'total_cents':base+fee,'items':[ITEM]}
    elif action=='create':
        state['created']=data
        result={'id':'test-order','number':10,'status':'accepted','total_cents':data['expected_total_cents']}
    elif action=='status':
        result={'id':'test-order','number':10,'status':state['status'],'fulfillment':'delivery','payment_method':'card_delivery','pay_on_delivery':True,'revision':1,'subtotal_cents':1000,'delivery_fee_cents':100,'card_fee_cents':66,'total_cents':1166,'paid_cents':0,'due_cents':1166,'refund_due_cents':0,'items':[ITEM],'payments':[],'changes':[],'created_at':'2026-11-08T20:00:00Z','updated_at':'2026-11-08T20:01:00Z','history':[{'status':'payment_pending','at':'2026-11-08T20:00:00Z'},{'status':'accepted','at':'2026-11-08T20:00:00Z'}]}
    else:
        raise AssertionError(f'Unexpected mock action: {action}')
    route.fulfill(status=200,headers={'Access-Control-Allow-Origin':'*'},content_type='application/json',body=json.dumps(result))

if __name__=='__main__':
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]
    proc=subprocess.Popen(['npm','run','dev','--','--host','127.0.0.1','--port',str(port),'--strictPort'],cwd=ROOT,env={**os.environ,'VITE_SUPABASE_URL':'http://127.0.0.1:54399','VITE_SUPABASE_PUBLISHABLE_KEY':'sb_publishable_delivery_fixture'},stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
    try:
        with sync_playwright() as p:
            browser=p.chromium.launch()
            ctx=browser.new_context(viewport={'width':390,'height':844})
            ctx.route('http://127.0.0.1:54399/**',mock)
            ctx.add_init_script("sessionStorage.setItem('planeta:online:cart', JSON.stringify([{line_id:'fixture-line',product_id:'test-burger',name:'Burger teste',price_cents:1000,quantity:1,modifiers:[],notes:''}]))")
            page=ctx.new_page();errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
            for attempt in range(50):
                try: page.goto(f'http://127.0.0.1:{port}/pedido');break
                except Exception: time.sleep(.1)
            page.locator('input[name=fulfillment]').nth(1).check()
            page.get_by_role('radio',name=re.compile('Cartão na entrega')).check()
            expect(page.get_by_text('Acréscimo cartão (6%)',exact=False)).to_be_visible()
            expect(page.get_by_text('R$ 11,66',exact=True)).to_be_visible()
            page.get_by_role('radio',name=re.compile('Dinheiro')).check()
            page.get_by_label('Preciso de troco').check()
            page.get_by_label('Troco para quanto? (R$)').fill('20,00')
            expect(page.get_by_label('Troco para quanto? (R$)')).to_have_value('20,00')
            page.get_by_role('radio',name=re.compile('Cartão na entrega')).check()
            page.get_by_label('Seu nome',exact=True).fill('Cliente teste')
            page.get_by_label('WhatsApp com DDD',exact=True).fill('(81) 99999-9999')
            page.get_by_label('Endereço completo para entrega',exact=True).fill('Rua teste, 123, Centro, Recife')
            page.get_by_label('Ponto de referência',exact=True).fill('Perto da farmacia')
            page.get_by_role('button',name='Confirmar pedido').click()
            expect(page.get_by_role('heading',name='Pedido #10',exact=True)).to_be_visible()
            expect(page.get_by_role('heading',name='Do preparo até você')).to_be_visible()
            expect(page.get_by_role('heading',name='Cartão na entrega',exact=True)).to_be_visible()
            assert state['created']['method']=='card_delivery'
            assert state['created']['expected_total_cents']==1166
            assert state['created']['change_for_cents'] is None
            assert state['created']['contact']['phone']=='5581999999999'
            assert state['created']['contact']['reference']=='Perto da farmacia'
            assert not any('price' in key for key in state['created']['items'][0])
            assert '#acompanhar=' in page.url
            state['status']='preparing'
            expect(page.locator('.customer-status strong')).to_have_text('Em preparo',timeout=10000)
            expect(page.locator('[aria-current=step]')).to_contain_text('Em preparo')
            assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth'), 'Horizontal overflow on mobile'
            assert not errors,errors
            browser.close()
            print('Delivery UI passed: exact fee, delivery contact, cash change, card submission, private tracker, mobile and status polling. Simulated API only.')
    finally:
        os.killpg(proc.pid,signal.SIGTERM);proc.wait()
