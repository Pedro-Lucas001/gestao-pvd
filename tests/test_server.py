import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server

class WorkflowTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        server.DB_PATH = Path(self.temp.name) / 'test.db'
        server.init_db()
        self.httpd = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        self.httpd.attempts = {}
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.httpd.server_port
        self.admin = {}
        self.employee = {}
        self.assertEqual(self.request('POST', '/api/setup', {'name':'Responsável', 'username':'admin', 'password':'test-password-123'})[0], 201)
        code, data, headers = self.request('POST', '/api/login', {'username':'admin','password':'test-password-123'})
        self.assertEqual(code, 200)
        self.admin = {'Cookie':headers['Set-Cookie'].split(';')[0], 'X-CSRF-Token':data['csrf']}
        self.assertEqual(self.request('POST','/api/users',{'name':'Atendente','username':'equipe','password':'employee-pass-123'},self.admin)[0],201)
        code,data,headers = self.request('POST','/api/login',{'username':'equipe','password':'employee-pass-123'})
        self.employee = {'Cookie':headers['Set-Cookie'].split(';')[0], 'X-CSRF-Token':data['csrf']}

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, method, path, body=None, headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.port)
        conn.request(method,path,json.dumps(body).encode() if body is not None else None,headers or {})
        response = conn.getresponse()
        data = json.loads(response.read())
        result = response.status, data, dict(response.getheaders())
        conn.close()
        return result

    def order(self, headers=None):
        return self.request('POST','/api/orders',{'customer':'Mesa 3','channel':'counter','payment':'pix','items':[{'name':'X-salada','qty':2,'price':1850}]},headers or self.employee)

    def test_payment_gate_and_full_kitchen_workflow(self):
        code, data, _ = self.order()
        self.assertEqual(code,201)
        oid = data['id']
        self.assertEqual(self.request('POST','/api/orders/status',{'id':oid,'status':'preparing'},self.employee)[0],409)
        self.assertEqual(self.request('POST','/api/orders/payment',{'id':oid},self.employee)[0],403)
        self.assertEqual(self.request('POST','/api/orders/payment',{'id':oid},self.admin)[0],200)
        self.assertEqual(self.request('POST','/api/orders/payment',{'id':oid},self.admin)[0],409)
        self.assertEqual(self.request('POST','/api/orders/status',{'id':oid,'status':'completed'},self.employee)[0],409)
        for status in ['preparing','ready','completed']:
            self.assertEqual(self.request('POST','/api/orders/status',{'id':oid,'status':status},self.employee)[0],200)
        row=self.request('GET','/api/orders',headers=self.admin)[1][0]
        self.assertEqual(row['total'],3700)
        self.assertEqual(row['status'],'completed')

    def test_roles_csrf_and_account_revocation(self):
        self.assertEqual(self.request('GET','/api/users',headers=self.employee)[0],403)
        self.assertEqual(self.request('POST','/api/users',{'name':'Intruso','username':'intruso','password':'long-password'},self.employee)[0],403)
        self.assertEqual(self.request('GET','/api/orders')[0],401)
        self.assertEqual(self.order({'Cookie':self.admin['Cookie']})[0],403)
        self.assertEqual(self.request('POST','/api/setup',{'name':'Outro','username':'outro','password':'long-password'})[0],409)
        users=self.request('GET','/api/users',headers=self.admin)[1]
        employee=next(u for u in users if u['role']=='employee')
        self.assertEqual(self.request('POST','/api/users/toggle',{'id':employee['id']},self.admin)[0],200)
        self.assertEqual(self.request('GET','/api/orders',headers=self.employee)[0],401)
        self.assertEqual(self.request('POST','/api/login',{'username':'equipe','password':'employee-pass-123'})[0],401)
        self.assertEqual(self.request('POST','/api/users/toggle',{'id':employee['id']},self.admin)[0],200)
        self.assertEqual(self.request('POST','/api/login',{'username':'equipe','password':'employee-pass-123'})[0],200)

    def test_validation_and_cancellation(self):
        self.assertEqual(self.request('POST','/api/orders',{'customer':'X','channel':'counter','payment':'pix','items':[]},self.admin)[0],400)
        oid=self.order()[1]['id']
        self.assertEqual(self.request('POST','/api/orders/status',{'id':oid,'status':'cancelled'},self.employee)[0],409)
        self.assertEqual(self.request('POST','/api/orders/status',{'id':oid,'status':'cancelled'},self.admin)[0],200)
        self.assertEqual(self.request('POST','/api/orders/payment',{'id':oid},self.admin)[0],409)
        cookie=self.admin['Cookie']
        self.assertEqual(self.request('POST','/api/logout',{},self.admin)[0],200)
        self.assertEqual(self.request('GET','/api/orders',headers={'Cookie':cookie})[0],401)

if __name__ == '__main__':
    unittest.main()
