"""Local browser QA for menu customizations. API/Auth are fixtures, not production."""
import json,os,re,signal,socket,subprocess,time
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright,expect
import ui_smoke
ROOT=Path(__file__).resolve().parents[1]
state={'flavors':['Frango','Presunto'],'quote':None,'saved':None,'version':2}
BASE=[{'product_id':'burger','name':'Burger teste','category':'hamburgueres','price_cents':1000,'allowed_modifiers':['Sem cebola'],'description':'Carne industrializada.'},
 {'product_id':'dog','name':'Dog teste','category':'dogoes','price_cents':600,'allowed_modifiers':['Sem cebola'],'description':'Dog na chapa.'},
 {'product_id':'pastel','name':'Pastel teste','category':'pasteis','price_cents':800,'allowed_modifiers':['Com tomate','Com milho','Com batata palha','Com ketchup','Com maionese','Sem acompanhamentos'],'description':'Pastel.'},
 {'product_id':'coxinha','name':'Mini coxinhas teste','category':'coxinhas','price_cents':200,'allowed_modifiers':[],'description':'Porcao.'},
 {'product_id':'extra-bacon','name':'Bacon','category':'adicionais','price_cents':300,'allowed_modifiers':[],'description':'Adicional.'}]
def catalog():
 result=json.loads(json.dumps(BASE))
 result[3]['allowed_modifiers']=['Sabor: '+f for f in state['flavors']]+(['Sabor: Mistas'] if len(state['flavors'])>1 else [])
 return result

def mock(route):
 if route.request.method=='OPTIONS':route.fulfill(status=200,headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*'});return
 path=urlsplit(route.request.url).path
 body=route.request.post_data_json or {}
 code=200
 if path.endswith('/rpc/public_menu'):
  result=[{**p,'id':p['product_id'],'image_path':'/menu/'+p['category']+'.svg'} for p in catalog() if p['category']!='adicionais' and (p['category']!='coxinhas' or state['flavors'])]
 elif path.endswith('/rpc/online_shop_config'):
  result={'coxinha_flavors':state['flavors']}
 elif path.endswith('/rpc/online_set_coxinha_flavors'):
  state['saved']=body;state['flavors']=body['p_flavors'];result=None
 elif path.endswith('/customer-api'):
  action=body['action']
  if action=='config':result={'enabled':True,'delivery_enabled':True,'delivery_fee_cents':500,'delivery_card_enabled':True,'cash_enabled':True,'whatsapp_number':'','payments':{'pix':False,'card':False,'manual_pix':False},'catalog':catalog()}
  elif action=='quote':
   state['quote']=body;subtotal=0
   for item in body['items']:
    product=next(p for p in catalog() if p['product_id']==item['product_id'])
    if product['category']=='coxinhas' and (len(item['modifiers'])!=1 or item['modifiers'][0] not in product['allowed_modifiers']):code=409;result={'code':'invalid_modifier','error':'Sabor indisponivel. Escolha outro sabor.'};break
    subtotal+=item['quantity']*(product['price_cents']+sum(next(p['price_cents'] for p in BASE if p['product_id']==extra) for extra in item.get('addons',[])))
   else:result={'subtotal_cents':subtotal,'delivery_fee_cents':0,'card_fee_cents':0,'total_cents':subtotal,'options_version':state['version']}
  else:raise AssertionError('Unexpected mutation '+action)
 else:
  ui_smoke.mock_api(route);return
 route.fulfill(status=code,headers={'Access-Control-Allow-Origin':'*'},content_type='application/json',body=json.dumps(result))

if __name__=='__main__':
 with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
 proc=subprocess.Popen(['npm','run','dev','--','--host','127.0.0.1','--port',str(port),'--strictPort'],cwd=ROOT,env={**os.environ,'VITE_SUPABASE_URL':'http://127.0.0.1:54399','VITE_SUPABASE_PUBLISHABLE_KEY':'sb_publishable_menu_fixture'},stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
 try:
  with sync_playwright() as p:
   browser=p.chromium.launch();context=browser.new_context(viewport={'width':390,'height':844});context.route('http://127.0.0.1:54399/**',mock)
   page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
   for _ in range(50):
    try:page.goto(f'http://127.0.0.1:{port}/cardapio');break
    except Exception:time.sleep(.1)
   expect(page.locator('[data-menu-product]')).to_have_count(4)
   expect(page.get_by_role('button',name='Adicionais',exact=True)).to_have_count(0)
   page.get_by_role('button',name='Adicionar Burger teste',exact=True).click()
   dialog=page.get_by_role('dialog');expect(dialog).to_be_visible()
   expect(dialog.get_by_text('Usamos carnes industrializadas.',exact=False)).to_be_visible()
   expect(dialog.get_by_text('Ponto:',exact=False)).to_have_count(0)
   dialog.get_by_label(re.compile('Bacon')).check();dialog.get_by_label('Quantidade',exact=True).fill('2')
   expect(dialog.get_by_role('button',name=re.compile('Adicionar ao pedido'))).to_contain_text('26,00')
   dialog.get_by_role('button',name=re.compile('Adicionar ao pedido')).click()
   page.get_by_role('button',name='Adicionar Pastel teste',exact=True).click()
   expect(dialog.get_by_role('group',name='Adicionais para este lanche')).to_have_count(0)
   dialog.get_by_label('tomate',exact=True).check();dialog.get_by_label('milho',exact=True).check()
   dialog.get_by_role('button',name=re.compile('Adicionar ao pedido')).click()
   for taste in ['Frango','Mistas / misturadas (sabores disponíveis)']:
    page.get_by_role('button',name='Adicionar Mini coxinhas teste',exact=True).click()
    expect(dialog.get_by_role('button',name=re.compile('Adicionar ao pedido'))).to_be_disabled()
    dialog.get_by_role('radio',name=taste,exact=True).check();dialog.get_by_role('button',name=re.compile('Adicionar ao pedido')).click()
   page.get_by_role('link',name='Revisar meu pedido').click()
   expect(page.locator('.customer-cart-line')).to_have_count(4)
   expect(page.locator('.customer-summary')).to_contain_text('38,00')
   assert state['quote']['items'][0]['addons']==['extra-bacon']
   assert state['quote']['items'][0]['quantity']==2
   assert state['quote']['items'][1]['modifiers']==['Com tomate','Com milho']
   assert all('price_cents' not in item for item in state['quote']['items'])
   # Old backends must not silently ignore extra prices during rollout.
   state['version']=1
   page.locator('.customer-cart-line').filter(has=page.get_by_role('heading',name='Burger teste',exact=True)).get_by_label(re.compile('Bacon')).uncheck()
   page.locator('.customer-cart-line').filter(has=page.get_by_role('heading',name='Burger teste',exact=True)).get_by_label(re.compile('Bacon')).check()
   expect(page.get_by_role('alert').filter(has_text='aguardando a atualização')).to_be_visible()
   state['version']=2
   state['flavors']=['Frango'];page.reload()
   expect(page.get_by_text('Esse sabor ficou indisponível.',exact=False)).to_be_visible()
   lines=page.locator('.customer-cart-line').filter(has=page.get_by_role('heading',name='Mini coxinhas teste',exact=True))
   lines.nth(1).get_by_role('radio',name='Frango',exact=True).check()
   expect(page.locator('.customer-summary')).to_contain_text('38,00')
   assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),'Mobile overflow'
   context.close()
   # Admin changes availability through the real admin component + mocked Auth.
   admin=browser.new_context(viewport={'width':1280,'height':900});admin.route('http://127.0.0.1:54399/**',mock);page=admin.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
   page.goto(f'http://127.0.0.1:{port}/login');page.get_by_label('E-mail',exact=True).fill('admin@fixture.test');page.get_by_label('Senha',exact=True).fill('test-password-only');page.get_by_role('button',name='Entrar no meu espaço').click()
   page.goto(f'http://127.0.0.1:{port}/catalogo')
   expect(page.get_by_role('heading',name='Mini coxinhas: sabores disponíveis hoje',exact=True)).to_be_visible()
   page.get_by_label('Disponível',exact=True).nth(1).check()
   page.get_by_label('Justificativa da disponibilidade').fill('Reposicao de frango e presunto')
   page.get_by_role('button',name='Salvar sabores do dia').click()
   expect(page.get_by_text('Disponibilidade atualizada',exact=False)).to_be_visible()
   assert state['saved']['p_flavors']==['Frango','Presunto']
   assert not errors,errors
   browser.close();print('Menu UI passed: nested priced extras, industrial meat, pastry choices, required/mixed flavors, stale availability, rollout price guard, mobile and admin availability. Simulated API/Auth only.')
 finally:os.killpg(proc.pid,signal.SIGTERM);proc.wait()
