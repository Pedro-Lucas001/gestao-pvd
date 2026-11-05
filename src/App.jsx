import { useState } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  Navigate,
  Outlet,
  NavLink,
  Link,
  useNavigate,
} from "react-router-dom";
import {
  ShoppingBag,
  ChefHat,
  LayoutDashboard,
  PackageSearch,
  ChartNoAxesCombined,
  Users,
  LogOut,
  LockKeyhole,
  Menu,
  X,
  ArrowRight,
  ShieldCheck,
  Flame,
  ExternalLink,
} from "lucide-react";
import AuthProvider from "./auth/AuthProvider";
import { useAuth } from "./auth/context";
import ProtectedRoute from "./auth/ProtectedRoute";
import { configured, supabase, rpc } from "./lib/supabase";
import { useConnection } from "./components/useConnection";
import ErrorBoundary from "./components/ErrorBoundary";
import PDV from "./pdv/PDV";
import KDS from "./kds/KDS";
import "./App.css";
function Brand() {
  return (
    <div className="brand">
      <span className="brand-mark">
        <Flame size={23} />
      </span>
      <div>
        <strong>
          PLANETA<span>LANCHES</span>
        </strong>
        <small>GESTÃO & OPERAÇÃO</small>
      </div>
    </div>
  );
}
const routes = [
  ["/pdv", "Frente de caixa", ShoppingBag, ["admin", "cashier"]],
  ["/cozinha", "Cozinha · KDS", ChefHat, ["admin", "kitchen"]],
  ["/dashboard", "Visão geral", LayoutDashboard, ["admin"]],
  ["/estoque", "Estoque e fichas", PackageSearch, ["admin"]],
  ["/relatorios", "Relatórios", ChartNoAxesCombined, ["admin"]],
  ["/equipe", "Equipe e acessos", Users, ["admin"]],
];
function Shell({ preview = false }) {
  const { profile, lock, signOut } = useAuth();
  const [menu, setMenu] = useState(false);
  const [lockError, setLockError] = useState("");
  const online = useConnection();
  const list = preview
    ? routes.slice(0, 1)
    : routes.filter((r) => r[3].includes(profile.role));
  return (
    <div className="app-shell">
      <aside className={`sidebar ${menu ? "expanded" : ""}`}>
        <div className="sidebar-brand">
          <Brand />
          <button
            className="icon-button mobile-toggle"
            aria-label="Fechar menu"
            onClick={() => setMenu(false)}
          >
            <X size={20} />
          </button>
        </div>
        <div className="store-card">
          <span className="store-icon">
            <ShoppingBag size={18} />
          </span>
          <div>
            <strong>Planeta Lanches</strong>
            <small>Carpina · Pernambuco</small>
          </div>
          <span className="live-dot" />
        </div>
        <div className="nav-caption">OPERAÇÃO</div>
        <nav>
          {list.map(([path, name, Icon]) => (
            <NavLink
              key={path}
              to={path}
              className={({ isActive }) => (isActive ? "active" : "")}
              onClick={() => setMenu(false)}
            >
              <Icon size={18} />
              <span>{name}</span>
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="brand-message">
            <Flame size={22} />
            <strong>
              Agilidade na operação.
              <br />
              Capricho em cada pedido.
            </strong>
            <p>Sabor que te leva mais longe.</p>
          </div>
          <div className="operator">
            <span className="avatar">
              {preview ? "PL" : profile.name.slice(0, 2).toUpperCase()}
            </span>
            <div>
              <strong>{preview ? "Prévia do PDV" : profile.name}</strong>
              <small>
                {preview
                  ? "Sem conexão com o banco"
                  : {
                      admin: "Administrador",
                      cashier: "Caixa",
                      kitchen: "Cozinha",
                    }[profile.role]}
              </small>
            </div>
            {!preview && (
              <button
                className="icon-button"
                aria-label="Sair da conta"
                onClick={signOut}
              >
                <LogOut size={17} />
              </button>
            )}
          </div>
        </div>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <button
            className="icon-button mobile-toggle"
            aria-label="Abrir menu"
            onClick={() => setMenu(true)}
          >
            <Menu size={20} />
          </button>
          <div>
            <span className="topbar-label">SEU ESPAÇO DE TRABALHO</span>
            <span className="environment">
              {import.meta.env.VITE_APP_ENV === "production"
                ? "PRODUÇÃO"
                : "STAGING"}
            </span>
          </div>
          <div className="topbar-actions">
            <span className={`online-state ${online ? "" : "offline"}`}>
              <span className="live-dot" />
              {online ? "Rede disponível" : "Sem internet"}
            </span>
            {!preview && profile.role === "cashier" && (
              <button
                className="terminal-button"
                onClick={() =>
                  lock().catch(() =>
                    setLockError(
                      "O terminal foi bloqueado localmente, mas não foi possível revogar a sessão de operação no servidor. Reconecte; a liberação anterior expira em até 15 minutos.",
                    ),
                  )
                }
              >
                <LockKeyhole size={14} />
                Bloquear terminal
              </button>
            )}
          </div>
        </header>
        {lockError && (
          <div className="offline-banner" role="alert">
            {lockError}
            <button className="text-button" onClick={() => setLockError("")}>
              Dispensar
            </button>
          </div>
        )}
        {preview && (
          <div className="preview-banner">
            <ShieldCheck size={17} />
            <span>
              <b>Prévia visual sem Supabase.</b> Explore o cardápio e
              personalize o rascunho. Login, caixa, envios e pagamentos ficam
              desativados até configurar o projeto.
            </span>
            <a
              href="https://supabase.com/dashboard"
              target="_blank"
              rel="noreferrer"
            >
              Criar projeto
              <ExternalLink size={13} />
            </a>
          </div>
        )}
        <main className="main-content">
          <ErrorBoundary area="workspace">
            {preview ? <PDV preview /> : <Outlet />}
          </ErrorBoundary>
        </main>
        <footer>
          <span>PLANETA LANCHES</span>
          <span>Organização em cada etapa. Sabor em cada detalhe.</span>
        </footer>
      </div>
    </div>
  );
}
function Login() {
  const { profile, loading, session, authError, retry, signOut } = useAuth();
  const online = useConnection();
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  if (!loading && profile && session && !authError)
    return (
      <Navigate to={profile.role === "kitchen" ? "/cozinha" : "/pdv"} replace />
    );
  return (
    <div className="auth-page">
      <section className="auth-art">
        <Brand />
        <div>
          <span className="eyebrow">O SABOR É NOSSO. O CONTROLE É SEU.</span>
          <h1>
            Uma operação mais leve.
            <br />
            <em>Um pedido de cada vez.</em>
          </h1>
          <p>Do balcão à cozinha, o Planeta continua em movimento.</p>
        </div>
        <img
          src="/brand/planeta-art.png"
          alt="Identidade ilustrada do Planeta Lanches"
        />
        <small>Carpina · PE · Feito com amor</small>
      </section>
      <section className="auth-form">
        <span className="eyebrow">BEM-VINDO AO SEU PLANETA</span>
        <h2>Vamos começar o turno?</h2>
        <p>
          Entre com seu acesso individual. As permissões acompanham sua função.
        </p>
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            setError("");
            const body = Object.fromEntries(new FormData(e.currentTarget));
            const { error } = await supabase.auth.signInWithPassword(body);
            if (error)
              setError(
                "Não foi possível entrar. Confira seu e-mail, senha e conexão.",
              );
            setBusy(false);
          }}
        >
          <label>
            E-mail
            <input
              type="email"
              name="email"
              autoComplete="username"
              required
              placeholder="voce@exemplo.com"
            />
          </label>
          <label>
            Senha
            <input
              type="password"
              name="password"
              autoComplete="current-password"
              required
              minLength={10}
              placeholder="Sua senha"
            />
          </label>
          {(error || authError) && (
            <p className="error-message" role="alert">
              {error || authError}
            </p>
          )}
          <button
            className="primary full"
            disabled={busy || loading || !online}
          >
            {busy ? "Entrando…" : "Entrar no meu espaço"}
            <ArrowRight size={17} />
          </button>
        </form>
        {session && (!profile || authError) && (
          <div className="auth-retry">
            <button className="secondary" onClick={retry}>
              Verificar perfil novamente
            </button>
            <button className="text-button" onClick={signOut}>
              Sair desta conta
            </button>
          </div>
        )}
        <div className="secure-note">
          <ShieldCheck size={17} />
          <span>
            Administradores usam e-mail e senha. Caixas também precisam do PIN
            pessoal para destravar o terminal.
          </span>
        </div>
        <Link className="text-button" to="/previa">
          Conhecer a interface, sem dados reais
          <ArrowRight size={13} />
        </Link>
      </section>
    </div>
  );
}
function Home() {
  const { profile } = useAuth();
  return (
    <Navigate to={profile?.role === "kitchen" ? "/cozinha" : "/pdv"} replace />
  );
}
function Denied() {
  const navigate = useNavigate();
  return (
    <div className="terminal-lock">
      <ShieldCheck size={37} />
      <span className="eyebrow">ACESSO RESTRITO</span>
      <h1>Esta área tem outro destino.</h1>
      <p>Seu perfil não tem permissão para acessar esta página.</p>
      <button
        className="primary"
        onClick={() => navigate("/", { replace: true })}
      >
        Voltar à minha área
        <ArrowRight size={17} />
      </button>
    </div>
  );
}
function AdminFoundation({ kind }) {
  const [team, setTeam] = useState([]),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  async function load() {
    const { data, error } = await supabase
      .from("profiles")
      .select("id,name,role,active,sector")
      .order("name");
    if (error) setError("Não foi possível carregar a equipe.");
    else setTeam(data);
  }
  const titles = {
    dashboard: "Visão geral",
    estoque: "Estoque e fichas técnicas",
    relatorios: "Relatórios operacionais",
    equipe: "Equipe e acessos",
  };
  return (
    <section className="foundation">
      <span className="eyebrow">ÁREA EXCLUSIVA DO ADMINISTRADOR</span>
      <h1>{titles[kind]}</h1>
      {kind === "equipe" ? (
        <>
          <p>
            Crie as contas pelo Supabase Auth com cadastro público desativado.
            Aqui, ative o acesso e configure os PINs. Novas contas ficam
            inativas por padrão.
          </p>
          <button className="secondary" onClick={load}>
            Carregar equipe
          </button>
          {team.map((p) => (
            <form
              className="staff-row"
              key={p.id}
              onSubmit={async (e) => {
                e.preventDefault();
                setError("");
                setBusy(true);
                const values = Object.fromEntries(
                  new FormData(e.currentTarget),
                );
                try {
                  if (
                    values.pin &&
                    (values.role !== "cashier" || values.active !== "true")
                  )
                    throw new Error(
                      "Configure PIN apenas para um caixa ativo. Nenhuma alteração foi salva.",
                    );
                  await rpc("manage_staff", {
                    p_user: p.id,
                    p_role: values.role,
                    p_sector: values.role === "kitchen" ? values.sector : null,
                    p_active: values.active === "true",
                  });
                  if (values.pin)
                    await rpc("set_staff_pin", {
                      p_user: p.id,
                      p_pin: values.pin,
                    });
                  await load();
                } catch (e) {
                  setError(e.message);
                } finally {
                  setBusy(false);
                }
              }}
            >
              <strong>{p.name}</strong>
              <label>
                Função
                <select name="role" defaultValue={p.role}>
                  <option value="cashier">Caixa</option>
                  <option value="kitchen">Cozinha</option>
                  <option value="admin">Administrador</option>
                </select>
              </label>
              <label>
                Setor
                <select name="sector" defaultValue={p.sector || "grill"}>
                  <option value="grill">Chapa</option>
                  <option value="fryer">Fritura</option>
                  <option value="bar">Bebidas</option>
                </select>
              </label>
              <label>
                Acesso
                <select name="active" defaultValue={String(p.active)}>
                  <option value="true">Ativo</option>
                  <option value="false">Bloqueado</option>
                </select>
              </label>
              <label>
                Novo PIN de caixa
                <input
                  name="pin"
                  type="password"
                  inputMode="numeric"
                  pattern="[0-9]{4}"
                  maxLength={4}
                  placeholder="Opcional"
                  autoComplete="new-password"
                />
              </label>
              <button className="primary" disabled={busy}>
                Salvar acesso
              </button>
            </form>
          ))}
        </>
      ) : (
        <>
          <p>
            A estrutura deste módulo está preparada no banco, com acesso
            restrito por RLS. O escopo desta entrega é o PDV inicial; esta tela
            não simula relatórios nem controles de estoque operacionais.
          </p>
          <div className="info-panel">
            <h2>
              {kind === "estoque"
                ? "Fichas técnicas e movimentos"
                : kind === "relatorios"
                  ? "Consultas de analytics"
                  : "Dados reais, sem números inventados"}
            </h2>
            <p>
              {kind === "estoque"
                ? "Ingredientes, unidades, custos e movimentos de baixa estão modelados. Cadastre receitas reais antes de ativar controle de insumos."
                : kind === "relatorios"
                  ? "Consultas de pico de vendas, margem e tempo por setor estão em docs/analytics.sql. Custos são exclusivos do administrador."
                  : "Crie o projeto Supabase e aplique as migrações para começar a operar o PDV. Os módulos de gestão serão evoluídos sobre a mesma base."}
            </p>
          </div>
        </>
      )}
      {error && (
        <p role="alert" className="error-message">
          {error}
        </p>
      )}
    </section>
  );
}
export default function App() {
  return (
    <ErrorBoundary area="application">
      <BrowserRouter>
        <AuthProvider>
          {!configured ? (
            <Shell preview />
          ) : (
            <Routes>
              <Route path="/previa" element={<Shell preview />} />
              <Route path="/login" element={<Login />} />
              <Route
                element={
                  <ProtectedRoute roles={["admin", "cashier", "kitchen"]} />
                }
              >
                <Route element={<Shell />}>
                  <Route index element={<Home />} />
                  <Route path="acesso-negado" element={<Denied />} />
                  <Route
                    element={<ProtectedRoute roles={["admin", "cashier"]} />}
                  >
                    <Route path="pdv" element={<PDV />} />
                  </Route>
                  <Route
                    element={<ProtectedRoute roles={["admin", "kitchen"]} />}
                  >
                    <Route path="cozinha" element={<KDS />} />
                  </Route>
                  <Route element={<ProtectedRoute roles={["admin"]} />}>
                    {["dashboard", "estoque", "relatorios", "equipe"].map(
                      (kind) => (
                        <Route
                          key={kind}
                          path={kind}
                          element={<AdminFoundation kind={kind} key={kind} />}
                        />
                      ),
                    )}
                  </Route>
                  <Route path="*" element={<Navigate to="/" replace />} />
                </Route>
              </Route>
            </Routes>
          )}
        </AuthProvider>
      </BrowserRouter>
    </ErrorBoundary>
  );
}
