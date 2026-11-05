import { lazy, Suspense, useState } from "react";
import {
  BrowserRouter,
  Navigate,
  NavLink,
  Outlet,
  Route,
  Routes,
  useLocation,
  useNavigate,
} from "react-router-dom";
import {
  ArrowRight,
  ChartNoAxesCombined,
  ChefHat,
  ExternalLink,
  Flame,
  LayoutDashboard,
  LockKeyhole,
  LogOut,
  Menu,
  PackageSearch,
  ShieldCheck,
  ShoppingBag,
  Users,
  X,
} from "lucide-react";
import AuthProvider from "./auth/AuthProvider";
import { useAuth } from "./auth/context";
import ProtectedRoute from "./auth/ProtectedRoute";
import { configured } from "./lib/supabase";
import { useConnection } from "./components/useConnection";
import ErrorBoundary from "./components/ErrorBoundary";
import PDV from "./pdv/PDV";
import KDS from "./kds/KDS";
import TerminalLock from "./auth/TerminalLock";
import Login from "./auth/Login";
import Brand from "./components/Brand";
import { homeForRole } from "./auth/permissions";
import "./App.css";
const DRE = lazy(() => import("./admin/DRE"));
const Reports = lazy(() => import("./admin/Reports"));
const Inventory = lazy(() => import("./admin/Inventory"));
const Catalog = lazy(() => import("./admin/Catalog"));
const Payments = lazy(() => import("./admin/Payments"));
const Audit = lazy(() => import("./admin/Audit"));
const OrderLinks = lazy(() => import("./admin/OrderLinks"));
const Team = lazy(() => import("./admin/Team"));
const Fulfillment = lazy(() => import("./admin/Fulfillment"));
const Integrations = lazy(() => import("./admin/Integrations"));
const PublicOrder = lazy(() => import("./public/PublicOrder"));

const routes = [
  ["/pdv", "Frente de caixa", ShoppingBag, ["admin", "cashier"]],
  ["/cozinha", "Cozinha · KDS", ChefHat, ["admin", "kitchen"]],
  ["/dashboard", "Visão geral", LayoutDashboard, ["admin"]],
  ["/estoque", "Estoque e fichas", PackageSearch, ["admin"]],
  ["/relatorios", "Relatórios", ChartNoAxesCombined, ["admin"]],
  ["/dre", "DRE gerencial", ChartNoAxesCombined, ["admin"]],
  ["/atendimento", "Atendimento e delivery", Users, ["admin", "cashier"]],
  ["/catalogo", "Cardápio", ShoppingBag, ["admin"]],
  ["/pagamentos", "Pagamentos e estornos", LayoutDashboard, ["admin"]],
  ["/auditoria", "Auditoria", ShieldCheck, ["admin"]],
  ["/links", "QR e autoatendimento", ExternalLink, ["admin"]],
  ["/integracoes", "Integrações", PackageSearch, ["admin"]],
  ["/equipe", "Equipe e acessos", Users, ["admin"]],
];
function Shell({ preview = false }) {
  const { profile, lock, signOut, locked } = useAuth();
  const [menu, setMenu] = useState(false);
  const [lockError, setLockError] = useState("");
  const online = useConnection();
  const staff = !preview && profile.role !== "admin";
  const path = useLocation().pathname;
  const route = routes.find((r) => r[0] === path);
  const gateRequired = path !== "/acesso-negado" &&
    (!route || preview || route[3].includes(profile.role));
  const list = preview
    ? routes.slice(0, 1)
    : routes.filter((r) => r[3].includes(profile.role));
  return (
    <div className={`app-shell ${staff ? "staff-shell" : ""}`}>
      {!staff && (
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
                  {preview ? "Sem conexão com o banco" : {
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
      )}
      <div className="workspace">
        <header className="topbar">
          {!staff && (
            <button
              className="icon-button mobile-toggle"
              aria-label="Abrir menu"
              onClick={() => setMenu(true)}
            >
              <Menu size={20} />
            </button>
          )}
          {staff && (
            <div className="staff-identity">
              <Brand />
              <span>
                {profile.name} ·{" "}
                {profile.role === "kitchen" ? "Cozinha" : "Caixa"}
              </span>
            </div>
          )}
          <div className={staff ? "staff-environment" : ""}>
            <span className="topbar-label">SEU ESPAÇO DE TRABALHO</span>
            <span className="environment">
              {import.meta.env.VITE_APP_ENV === "production"
                ? "PRODUÇÃO"
                : "STAGING"}
            </span>
          </div>
          <div className="topbar-actions">
            {staff && (
              <button className="terminal-button" onClick={signOut}>
                <LogOut size={17} />Trocar funcionário
              </button>
            )}
            <span className={`online-state ${online ? "" : "offline"}`}>
              <span className="live-dot" />
              {online ? "Rede disponível" : "Sem internet"}
            </span>
            {!preview &&
              ["cashier", "kitchen", "admin"].includes(profile.role) && (
              <button
                className="terminal-button"
                onClick={() =>
                  lock().catch(() =>
                    setLockError(
                      "O terminal foi bloqueado localmente, mas não foi possível revogar a sessão de operação no servidor. Reconecte; a liberação anterior expira em até 15 minutos.",
                    )
                  )}
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
              <b>Prévia visual sem Supabase.</b>{" "}
              Explore o cardápio e personalize o rascunho. Login, caixa, envios
              e pagamentos ficam desativados até configurar o projeto.
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
            {preview
              ? <PDV preview />
              : locked && gateRequired
              ? <TerminalLock />
              : (
                <div className="route-transition" key={path}>
                  <Outlet />
                </div>
              )}
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
function Home() {
  const { profile } = useAuth();
  return <Navigate to={homeForRole(profile?.role)} replace />;
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
function AdminModule({ kind }) {
  const views = {
    dashboard: Reports,
    relatorios: Reports,
    dre: DRE,
    estoque: Inventory,
    equipe: Team,
    catalogo: Catalog,
    pagamentos: Payments,
    auditoria: Audit,
    links: OrderLinks,
    integracoes: Integrations,
  };
  const View = views[kind];
  return (
    <Suspense fallback={<div className="loading">Carregando gestão…</div>}>
      <View />
    </Suspense>
  );
}
function PublicAware({ children }) {
  const path = useLocation().pathname;
  return path === "/pedido"
    ? (
      <Suspense fallback={<div className="loading">Carregando cardápio…</div>}>
        <PublicOrder />
      </Suspense>
    )
    : children;
}
export default function App() {
  return (
    <ErrorBoundary area="application">
      <BrowserRouter>
        <AuthProvider>
          <PublicAware>
            {!configured ? <Shell preview /> : (
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
                      <Route
                        path="atendimento"
                        element={
                          <Suspense
                            fallback={
                              <div className="loading">
                                Carregando atendimentos…
                              </div>
                            }
                          >
                            <Fulfillment />
                          </Suspense>
                        }
                      />
                    </Route>
                    <Route
                      element={<ProtectedRoute roles={["admin", "kitchen"]} />}
                    >
                      <Route path="cozinha" element={<KDS />} />
                    </Route>
                    <Route element={<ProtectedRoute roles={["admin"]} />}>
                      {[
                        "dashboard",
                        "estoque",
                        "relatorios",
                        "dre",
                        "equipe",
                        "catalogo",
                        "pagamentos",
                        "auditoria",
                        "links",
                        "integracoes",
                      ].map((kind) => (
                        <Route
                          key={kind}
                          path={kind}
                          element={<AdminModule kind={kind} key={kind} />}
                        />
                      ))}
                    </Route>
                    <Route path="*" element={<Navigate to="/" replace />} />
                  </Route>
                </Route>
              </Routes>
            )}
          </PublicAware>
        </AuthProvider>
      </BrowserRouter>
    </ErrorBoundary>
  );
}
