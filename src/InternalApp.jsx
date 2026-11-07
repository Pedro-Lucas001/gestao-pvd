import { lazy, Suspense, useEffect, useState } from "react";
import {
  Link,
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
import { useConnection } from "./components/useConnection";
import ErrorBoundary from "./components/ErrorBoundary";
import PDV from "./pdv/PDV";
import KDS from "./kds/KDS";
import TerminalLock from "./auth/TerminalLock";
import Login from "./auth/Login";
import Brand from "./components/Brand";
import { homeForRole } from "./auth/permissions";
import { accessModules } from "./auth/modules";
import "./App.css";
const OnlineOrders = lazy(() => import("./admin/OnlineOrders"));
const AdminDashboard = lazy(() => import("./admin/AdminDashboard"));
const StaffHome = lazy(() => import("./auth/StaffHome"));
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

const moduleIcons = {
  sales: ShoppingBag,
  kitchen: ChefHat,
  dashboard: LayoutDashboard,
  inventory: PackageSearch,
  reports: ChartNoAxesCombined,
  team: Users,
  security: ShieldCheck,
  links: ExternalLink,
};
const routes = accessModules.map((module) => [
  module.path,
  module.label,
  moduleIcons[module.icon],
  module.roles,
]);
function Shell() {
  const { profile, lock, signOut, locked } = useAuth();
  const [menu, setMenu] = useState(false);
  const [lockError, setLockError] = useState("");
  const online = useConnection();
  const staff = profile.role !== "admin";
  const path = useLocation().pathname;
  const route = routes.find((r) => r[0] === path);
  const gateRequired =
    path !== "/acesso-negado" && (!route || route[3].includes(profile.role));
  const list = routes.filter((r) => r[3].includes(profile.role));
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
                {profile.name.slice(0, 2).toUpperCase()}
              </span>
              <div>
                <strong>{profile.name}</strong>
                <small>
                  {
                    {
                      admin: "Administrador",
                      cashier: "Caixa",
                      kitchen: "Cozinha",
                    }[profile.role]
                  }
                </small>
              </div>
              {
                <button
                  className="icon-button"
                  aria-label="Sair da conta"
                  onClick={signOut}
                >
                  <LogOut size={17} />
                </button>
              }
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
          {staff && (
            <nav className="staff-navigation" aria-label="Áreas de trabalho">
              {list.map(([path, label]) => (
                <NavLink key={path} to={path}>
                  {label}
                </NavLink>
              ))}
            </nav>
          )}
          <div className="topbar-actions">
            <Link to="/cardapio" className="terminal-button public-menu-link">
              <ExternalLink size={14} />
              Cardápio público
            </Link>
            {staff && (
              <button className="terminal-button" onClick={signOut}>
                <LogOut size={17} />
                Trocar funcionário
              </button>
            )}
            <span className={`online-state ${online ? "" : "offline"}`}>
              <span className="live-dot" />
              {online ? "Rede disponível" : "Sem internet"}
            </span>
            {["cashier", "kitchen", "admin"].includes(profile.role) && (
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
        <main className="main-content">
          <ErrorBoundary area="workspace">
            {locked && gateRequired ? (
              <TerminalLock />
            ) : (
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
        onClick={() => navigate("/sistema", { replace: true })}
      >
        Voltar à minha área
        <ArrowRight size={17} />
      </button>
    </div>
  );
}
function AdminModule({ kind }) {
  const views = {
    "pedidos-online": OnlineOrders,
    funcionario: StaffHome,
    dashboard: AdminDashboard,
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
export default function InternalApp() {
  useEffect(() => {
    document.title = "Planeta Lanches · Área interna";
  }, []);
  return (
    <AuthProvider>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          element={<ProtectedRoute roles={["admin", "cashier", "kitchen"]} />}
        >
          <Route element={<Shell />}>
            <Route path="/sistema" element={<Home />} />
            <Route path="/acesso-negado" element={<Denied />} />
            {accessModules.map(({ path, roles }) => (
              <Route key={path} element={<ProtectedRoute roles={roles} />}>
                <Route
                  path={path}
                  element={
                    path === "/pdv" ? (
                      <PDV />
                    ) : path === "/cozinha" ? (
                      <KDS />
                    ) : path === "/atendimento" ? (
                      <Suspense
                        fallback={
                          <div className="loading">
                            Carregando atendimentos…
                          </div>
                        }
                      >
                        <Fulfillment />
                      </Suspense>
                    ) : (
                      <AdminModule kind={path.slice(1)} />
                    )
                  }
                />
              </Route>
            ))}
            <Route path="*" element={<Navigate to="/sistema" replace />} />
          </Route>
        </Route>
      </Routes>
    </AuthProvider>
  );
}
