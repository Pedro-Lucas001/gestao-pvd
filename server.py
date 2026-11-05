import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import time
from http import cookies
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get('PLANETA_DB', str(ROOT / '.data' / 'planeta.db')))
STATUSES = ['pending_payment', 'queued', 'preparing', 'ready', 'completed', 'cancelled']

def connect():
    db = sqlite3.connect(DB_PATH)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA foreign_keys=ON')
    return db

def init_db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with connect() as db:
        db.executescript('''
        CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, name TEXT NOT NULL, username TEXT NOT NULL UNIQUE, password TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('admin','employee')), active INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id), expires REAL NOT NULL, csrf TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS orders(id INTEGER PRIMARY KEY, customer TEXT NOT NULL, channel TEXT NOT NULL, items TEXT NOT NULL, total INTEGER NOT NULL, payment TEXT NOT NULL, paid INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'pending_payment', notes TEXT NOT NULL DEFAULT '', created REAL NOT NULL);
        ''')

def password_hash(password):
    salt = secrets.token_hex(16)
    digest = hashlib.scrypt(password.encode(), salt=salt.encode(), n=16384, r=8, p=1).hex()
    return salt + ':' + digest

def password_matches(password, stored):
    salt, digest = stored.split(':')
    return hmac.compare_digest(hashlib.scrypt(password.encode(), salt=salt.encode(), n=16384, r=8, p=1).hex(), digest)

def public_user(row):
    return {k: row[k] for k in ('id', 'name', 'username', 'role')}

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT / 'public'), **kwargs)

    def reply(self, code, value, cookie=None):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        if cookie:
            self.send_header('Set-Cookie', cookie)
        self.end_headers()
        self.wfile.write(data)

    def end_headers(self):
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Content-Security-Policy', "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; frame-ancestors 'none'")
        super().end_headers()

    def session(self, db):
        jar = cookies.SimpleCookie()
        try:
            jar.load(self.headers.get('Cookie', ''))
            token = jar['planeta_session'].value if 'planeta_session' in jar else ''
        except cookies.CookieError:
            token = ''
        return db.execute('SELECT users.*, sessions.csrf, sessions.token FROM sessions JOIN users ON users.id=sessions.user_id WHERE token=? AND expires>? AND active=1', (token, time.time())).fetchone()

    def do_GET(self):
        if urlsplit(self.path).path.startswith('/api/'):
            self.api('GET')
        else:
            super().do_GET()

    def do_POST(self):
        self.api('POST')

    def api(self, method):
        try:
            with connect() as db:
                self.handle_api(db, method)
        except (ValueError, KeyError, TypeError, json.JSONDecodeError):
            self.reply(400, {'error': 'Confira os dados informados.'})
        except sqlite3.IntegrityError:
            self.reply(409, {'error': 'Este nome de usuário já está em uso.'})

    def handle_api(self, db, method):
        path = urlsplit(self.path).path
        body = {}
        if method == 'POST':
            origin = self.headers.get('Origin')
            if origin and urlsplit(origin).netloc != self.headers.get('Host'):
                return self.reply(403, {'error': 'Origem não permitida.'})
            length = int(self.headers.get('Content-Length', '0'))
            if length < 0 or length > 32768:
                return self.reply(413, {'error': 'Dados muito grandes.'})
            body = json.loads(self.rfile.read(length) or b'{}')
            if not isinstance(body, dict):
                raise ValueError()
        user = self.session(db)
        if path == '/api/session' and method == 'GET':
            setup = not db.execute('SELECT 1 FROM users LIMIT 1').fetchone()
            return self.reply(200, {'user': public_user(user) if user else None, 'csrf': user['csrf'] if user else None, 'setup': setup})
        if path == '/api/setup' and method == 'POST':
            # Serialize first-admin creation, including the emptiness check.
            db.execute('BEGIN IMMEDIATE')
            if db.execute('SELECT 1 FROM users LIMIT 1').fetchone():
                return self.reply(409, {'error': 'O administrador já foi cadastrado.'})
            self.add_user(db, body, 'admin')
            return self.reply(201, {'ok': True})
        if path == '/api/login' and method == 'POST':
            # Bound attempts per source to reduce password guessing.
            now = time.time()
            attempts = self.server.attempts
            ip = self.client_address[0]
            recent = [t for t in attempts.get(ip, []) if t > now - 300]
            attempts[ip] = recent
            if len(recent) >= 10:
                return self.reply(429, {'error': 'Muitas tentativas. Aguarde cinco minutos.'})
            recent.append(now)
            row = db.execute('SELECT * FROM users WHERE username=? AND active=1', (str(body.get('username', '')).lower().strip(),)).fetchone()
            password = body.get('password', '')
            if not isinstance(password, str) or len(password) > 256 or not row or not password_matches(password, row['password']):
                return self.reply(401, {'error': 'Usuário ou senha incorretos.'})
            token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(24)
            db.execute('DELETE FROM sessions WHERE expires<?', (now,))
            db.execute('INSERT INTO sessions VALUES(?,?,?,?)', (token, row['id'], now + 43200, csrf))
            secure = '; Secure' if os.environ.get('PLANETA_SECURE_COOKIE') == '1' else ''
            return self.reply(200, {'user': public_user(row), 'csrf': csrf}, f'planeta_session={token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=43200{secure}')
        if not user:
            return self.reply(401, {'error': 'Entre para continuar.'})
        if method == 'POST' and not hmac.compare_digest(self.headers.get('X-CSRF-Token', ''), user['csrf']):
            return self.reply(403, {'error': 'Sessão inválida. Entre novamente.'})
        if path == '/api/logout' and method == 'POST':
            db.execute('DELETE FROM sessions WHERE token=?', (user['token'],))
            return self.reply(200, {'ok': True}, 'planeta_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0')
        if path.startswith('/api/users'):
            if user['role'] != 'admin':
                return self.reply(403, {'error': 'Apenas administradores podem gerenciar a equipe.'})
            if method == 'GET' and path == '/api/users':
                return self.reply(200, [dict(r) for r in db.execute('SELECT id,name,username,role,active FROM users ORDER BY id')])
            if method == 'POST' and path == '/api/users':
                self.add_user(db, body, 'employee')
                return self.reply(201, {'ok': True})
            if method == 'POST' and path == '/api/users/toggle':
                target = db.execute('SELECT * FROM users WHERE id=?', (body['id'],)).fetchone()
                if not target or target['role'] == 'admin':
                    return self.reply(400, {'error': 'O acesso do administrador não pode ser desativado aqui.'})
                db.execute('UPDATE users SET active=1-active WHERE id=?', (target['id'],))
                db.execute('DELETE FROM sessions WHERE user_id=?', (target['id'],))
                return self.reply(200, {'ok': True})
        if path == '/api/orders' and method == 'GET':
            rows = [dict(r) for r in db.execute('SELECT * FROM orders ORDER BY id DESC')]
            for row in rows:
                row['items'] = json.loads(row['items'])
            return self.reply(200, rows)
        if path == '/api/orders' and method == 'POST':
            customer = str(body['customer']).strip()
            channel, payment = body['channel'], body['payment']
            items = body['items']
            if not customer or len(customer) > 100 or channel not in ['counter', 'whatsapp'] or payment not in ['pix', 'cash', 'card'] or not isinstance(items, list) or not 1 <= len(items) <= 30:
                raise ValueError()
            total = 0
            clean = []
            for item in items:
                name = str(item['name']).strip()
                qty, price = item['qty'], item['price']
                if not name or len(name) > 120 or type(qty) is not int or type(price) is not int or not 1 <= qty <= 100 or not 1 <= price <= 100000:
                    raise ValueError()
                clean.append({'name': name, 'qty': qty, 'price': price})
                total += qty * price
            notes = str(body.get('notes', '')).strip()[:1000]
            result = db.execute('INSERT INTO orders(customer,channel,items,total,payment,notes,created) VALUES(?,?,?,?,?,?,?)', (customer, channel, json.dumps(clean), total, payment, notes, time.time()))
            return self.reply(201, {'id': result.lastrowid})
        if path == '/api/orders/status' and method == 'POST':
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT * FROM orders WHERE id=?', (body['id'],)).fetchone()
            if not row:
                return self.reply(404, {'error': 'Pedido não encontrado.'})
            status = body['status']
            transitions = {'queued': 'preparing', 'preparing': 'ready', 'ready': 'completed'}
            if status == 'cancelled' and user['role'] == 'admin' and row['status'] not in ['completed', 'cancelled']:
                pass
            elif transitions.get(row['status']) != status or not row['paid']:
                return self.reply(409, {'error': 'Este pedido não pode avançar. Confira o pagamento e a etapa atual.'})
            db.execute('UPDATE orders SET status=? WHERE id=?', (status, row['id']))
            return self.reply(200, {'ok': True})
        if path == '/api/orders/payment' and method == 'POST':
            if user['role'] != 'admin':
                return self.reply(403, {'error': 'Somente o administrador pode confirmar um pagamento manual.'})
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT * FROM orders WHERE id=?', (body['id'],)).fetchone()
            if not row or row['status'] != 'pending_payment':
                return self.reply(409, {'error': 'Pedido indisponível para confirmação.'})
            db.execute("UPDATE orders SET paid=1,status='queued' WHERE id=?", (row['id'],))
            return self.reply(200, {'ok': True})
        return self.reply(404, {'error': 'Recurso não encontrado.'})

    def add_user(self, db, body, role):
        name, username, password = body['name'], body['username'], body['password']
        if not all(isinstance(x, str) for x in [name, username, password]):
            raise ValueError()
        name, username = name.strip(), username.strip().lower()
        if not 2 <= len(name) <= 80 or not 3 <= len(username) <= 40 or not username.isascii() or not all(c.isalnum() or c in '._-' for c in username) or not 10 <= len(password) <= 256:
            raise ValueError()
        db.execute('INSERT INTO users(name,username,password,role) VALUES(?,?,?,?)', (name, username, password_hash(password), role))

if __name__ == '__main__':
    init_db()
    server = ThreadingHTTPServer((os.environ.get('HOST', '127.0.0.1'), int(os.environ.get('PORT', '3000'))), Handler)
    server.attempts = {}
    print('Planeta Lanches iniciado na porta ' + str(server.server_port), flush=True)
    server.serve_forever()
