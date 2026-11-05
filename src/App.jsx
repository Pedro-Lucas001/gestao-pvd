import { useState, useEffect, useCallback, useRef } from "react";
import {
  LayoutDashboard,
  ShoppingBag,
  ChefHat,
  UtensilsCrossed,
  Users,
  Settings,
  LogOut,
  Search,
  Plus,
  Minus,
  X,
  ArrowUpRight,
  ArrowRight,
  Check,
  Clock3,
  Wallet,
  SlidersHorizontal,
  ChevronRight,
  ShoppingBasket,
  Flame,
  CircleHelp,
  Sparkles,
  MapPin,
  Phone,
  ShieldCheck,
  LoaderCircle,
  Banknote,
  Menu,
  CheckCheck,
} from "lucide-react";
import products from "./data/menu.json";
import { request, setCsrf } from "./services/api";
import "./App.css";

const money = (n) =>
  (n / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
const categories = [
  { id: "all", name: "Todos os produtos", icon: "✦" },
  { id: "hamburgueres", name: "Hambúrgueres", icon: "🍔" },
  { id: "dogoes", name: "Dogões", icon: "🌭" },
  { id: "porcoes", name: "Porções", icon: "🍟" },
  { id: "pasteis", name: "Pastéis", icon: "🥟" },
  { id: "coxinhas", name: "Mini coxinhas", icon: "◈" },
  { id: "bebidas", name: "Bebidas", icon: "🥤" },
  { id: "adicionais", name: "Adicionais", icon: "＋" },
];
const labels = {
  pending_payment: "Aguardando pagamento",
  queued: "Na fila",
  preparing: "Em preparo",
  ready: "Pronto",
  completed: "Concluído",
  cancelled: "Cancelado",
};
const nextStatus = {
  queued: "preparing",
  preparing: "ready",
  ready: "completed",
};
const nextLabel = {
  queued: "Iniciar preparo",
  preparing: "Marcar como pronto",
  ready: "Concluir pedido",
};
const nav = [
  { id: "overview", name: "Visão geral", icon: LayoutDashboard, admin: true },
  { id: "orders", name: "Pedidos", icon: ShoppingBag },
  { id: "kitchen", name: "Cozinha", icon: ChefHat },
  { id: "menu", name: "Cardápio", icon: UtensilsCrossed, admin: true },
  { id: "team", name: "Equipe e acessos", icon: Users, admin: true },
  { id: "settings", name: "Integrações", icon: Settings, admin: true },
];
const normalize = (s) =>
  s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
function Brand({ large = false }) {
  return (
    <div className={`brand ${large ? "large" : ""}`}>
      <div className="brand-planet">
        <span />
      </div>
      <div>
        <strong>PLANETA</strong>
        <em>Lanches</em>
      </div>
    </div>
  );
}
function Badge({ status }) {
  return (
    <span className={`badge ${status}`}>
      <i />
      {labels[status]}
    </span>
  );
}
function App() {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);
  const [initialError, setInitialError] = useState("");
  const [page, setPage] = useState("overview");
  const [orders, setOrders] = useState([]);
  const [team, setTeam] = useState([]);
  const [notice, setNotice] = useState("");
  const [modal, setModal] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [mobileNav, setMobileNav] = useState(false);
  const dialogRef = useRef(null);
  const admin = session?.user?.role === "admin";
  const authenticated = Boolean(session?.user);
  const toast = useCallback((text) => setNotice(text), []);
  const reload = useCallback(async () => {
    try {
      const data = await request("orders");
      setOrders(data);
      if (admin) setTeam(await request("users"));
    } catch (e) {
      if (e.status === 401) {
        setSession({ user: null, setup: false });
        setCsrf("");
        setModal(null);
      }
      toast(e.message);
    }
  }, [admin, toast]);
  useEffect(() => {
    const controller = new AbortController();
    request("session", undefined, controller.signal)
      .then((s) => {
        setSession(s);
        setCsrf(s.csrf);
        setPage(s.user?.role === "employee" ? "orders" : "overview");
        setLoading(false);
      })
      .catch((e) => {
        if (e.name !== "AbortError") {
          setInitialError(
            "Não foi possível conectar. Confira se o servidor está iniciado.",
          );
          setLoading(false);
        }
      });
    return () => controller.abort();
  }, []);
  useEffect(() => {
    if (!authenticated) return;
    const start = setTimeout(reload, 0);
    const timer = setInterval(reload, 15000);
    return () => {
      clearTimeout(start);
      clearInterval(timer);
    };
  }, [authenticated, reload]);
  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(""), 5000);
    return () => clearTimeout(timer);
  }, [notice]);
  useEffect(() => {
    if (modal) dialogRef.current?.showModal();
    else dialogRef.current?.close();
  }, [modal]);
  async function signIn(event) {
    event.preventDefault();
    setBusy(true);
    setError("");
    const values = Object.fromEntries(new FormData(event.currentTarget));
    try {
      if (session.setup) {
        await request("setup", values);
        setSession({ user: null, setup: false });
      }
      const s = await request("login", values);
      setSession(s);
      setCsrf(s.csrf);
      setPage(s.user.role === "admin" ? "overview" : "orders");
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  async function logout() {
    try {
      await request("logout", {});
      setSession({ user: null, setup: false });
      setCsrf("");
      setOrders([]);
      setTeam([]);
      setModal(null);
    } catch (e) {
      toast(e.message);
    }
  }
  async function mutate(path, data, message) {
    setBusy(true);
    setError("");
    try {
      await request(path, data);
      setModal(null);
      toast(message);
      await reload();
      return true;
    } catch (e) {
      setError(e.message);
      toast(e.message);
      return false;
    } finally {
      setBusy(false);
    }
  }
  const open = (value) => {
    setError("");
    setModal(value);
  };
  const go = (value) => {
    setPage(value);
    setMobileNav(false);
  };
  const today = orders.filter(
    (o) =>
      new Date(o.created * 1000).toDateString() === new Date().toDateString(),
  );
  if (loading)
    return (
      <div className="loading">
        <Brand large />
        <LoaderCircle className="spin" />
        <p>Preparando seu Planeta…</p>
      </div>
    );
  if (initialError)
    return (
      <div className="loading">
        <Brand large />
        <p role="alert">{initialError}</p>
        <button className="primary" onClick={() => location.reload()}>
          Tentar novamente
        </button>
      </div>
    );
  if (!authenticated)
    return (
      <main className="auth-page">
        <div className="auth-art">
          <Brand large />
          <div className="auth-copy">
            <span className="eyebrow">
              <Sparkles size={14} /> SABOR QUE TE LEVA MAIS LONGE
            </span>
            <h1>
              Um universo de sabor.
              <br />
              <span>Uma gestão no controle.</span>
            </h1>
            <p>Do balcão à cozinha, seu Planeta conectado.</p>
          </div>
          <img
            src="/brand/planeta-art.png"
            alt="Ilustração inspirada na identidade do Planeta Lanches"
          />
          <div className="auth-location">
            <MapPin size={14} /> Carpina · PE{" "}
            <span>Feito com amor, servido com organização.</span>
          </div>
        </div>
        <section className="auth-form">
          <div className="auth-mobile-brand">
            <Brand />
          </div>
          <span className="section-kicker">PAINEL DE GESTÃO</span>
          <h2>
            {session?.setup
              ? "O seu Planeta começa aqui."
              : "Bom ter você por aqui."}
          </h2>
          <p>
            {session?.setup
              ? "Cadastre o administrador para começar a organizar a operação."
              : "Entre na sua conta para acompanhar a operação."}
          </p>
          <form onSubmit={signIn}>
            {session?.setup && (
              <label>
                Seu nome
                <input
                  name="name"
                  required
                  minLength={2}
                  maxLength={80}
                  autoComplete="name"
                  placeholder="Como podemos chamar você?"
                />
              </label>
            )}
            <label>
              Usuário
              <input
                name="username"
                required
                minLength={3}
                maxLength={40}
                pattern="[A-Za-z0-9._-]+"
                autoComplete="username"
                placeholder="Seu usuário"
              />
            </label>
            <label>
              Senha
              <input
                name="password"
                type="password"
                required
                minLength={10}
                maxLength={256}
                autoComplete={
                  session?.setup ? "new-password" : "current-password"
                }
                placeholder="Pelo menos 10 caracteres"
              />
            </label>
            {error && (
              <p className="form-error" role="alert">
                {error}
              </p>
            )}
            <button className="primary full" disabled={busy}>
              {busy
                ? "Aguarde…"
                : session?.setup
                  ? "Criar meu acesso"
                  : "Entrar no painel"}
              <ArrowRight size={17} />
            </button>
          </form>
          <div className="secure-note">
            <ShieldCheck size={16} />
            {session?.setup
              ? "O primeiro acesso terá perfil de administrador."
              : "Acesso individual para cada pessoa da equipe."}
          </div>
        </section>
      </main>
    );
  return (
    <div className="app-shell">
      <aside className={`sidebar ${mobileNav ? "expanded" : ""}`}>
        <div className="sidebar-brand">
          <Brand />
          <button
            className="icon-button mobile-toggle"
            aria-label="Fechar menu"
            onClick={() => setMobileNav(false)}
          >
            <X size={20} />
          </button>
        </div>
        <div className="store">
          <div className="store-symbol">
            <ShoppingBag size={18} />
          </div>
          <div>
            <strong>Planeta Lanches</strong>
            <small>Carpina, Pernambuco</small>
          </div>
          <span className="live-dot" />
        </div>
        <div className="nav-caption">SEU ESPAÇO</div>
        <nav>
          {nav
            .filter((n) => !n.admin || admin)
            .map((n, i) => {
              const Icon = n.icon;
              return (
                <button
                  key={n.id}
                  className={`${page === n.id ? "active" : ""} ${i === 3 ? "nav-divider" : ""}`}
                  onClick={() => go(n.id)}
                >
                  <Icon size={18} />
                  {n.name}
                  {n.id === "orders" && (
                    <span className="nav-count">
                      {
                        orders.filter(
                          (o) => !["completed", "cancelled"].includes(o.status),
                        ).length
                      }
                    </span>
                  )}
                  {page === n.id && <span className="nav-active-dot" />}
                </button>
              );
            })}
        </nav>
        <div className="sidebar-bottom">
          <div className="brand-message">
            <Sparkles size={20} />
            <strong>Seu sabor vai mais longe.</strong>
            <p>
              A organização cuida da rotina.
              <br />
              Você cuida do capricho.
            </p>
          </div>
          <div className="sidebar-help">
            <CircleHelp size={15} />
            <span>Precisa de uma pausa?</span>
            <span>✦</span>
          </div>
          <div className="user-profile">
            <span className="avatar">
              {session.user.name.slice(0, 2).toUpperCase()}
            </span>
            <div>
              <strong>{session.user.name}</strong>
              <small>{admin ? "Administrador" : "Funcionário"}</small>
            </div>
            <button className="icon-button" onClick={logout} aria-label="Sair">
              <LogOut size={17} />
            </button>
          </div>
        </div>
      </aside>
      <div className="main-shell">
        <header className="topbar">
          <button
            className="icon-button mobile-toggle"
            aria-label="Abrir menu"
            onClick={() => setMobileNav(!mobileNav)}
          >
            <Menu size={21} />
          </button>
          <div>
            Planeta Lanches <ChevronRight size={13} />
            <strong>{nav.find((n) => n.id === page)?.name}</strong>
          </div>
          <div className="topbar-right">
            <span className="session-indicator">
              <span className="live-dot" />
              Sessão ativa
            </span>
            <span className="top-divider" />
            <span className="top-avatar">{session.user.name[0]}</span>
          </div>
        </header>
        <main className="content">
          {page === "overview" && (
            <>
              <PageHeading
                kicker="SEU PLANETA EM TEMPO REAL"
                title={`Olá, ${session.user.name.split(" ")[0]}. Vamos nessa?`}
                description="Uma visão da operação, do primeiro pedido à última entrega."
                action={
                  <button
                    className="primary"
                    onClick={() => open({ type: "order" })}
                  >
                    <Plus size={17} />
                    Novo pedido
                  </button>
                }
              />
              <Hero onClick={() => go("menu")} />
              <section className="stats-grid">
                {[
                  {
                    label: "Pedidos de hoje",
                    value: today.length,
                    detail: "Todos os canais",
                    icon: ShoppingBag,
                    color: "gold",
                  },
                  {
                    label: "Recebimentos de hoje",
                    value: money(
                      today
                        .filter((o) => o.paid && o.status !== "cancelled")
                        .reduce((a, o) => a + o.total, 0),
                    ),
                    detail: "Confirmados manualmente",
                    icon: Wallet,
                    color: "green",
                  },
                  {
                    label: "Em preparo",
                    value: orders.filter((o) => o.status === "preparing")
                      .length,
                    detail: "Capricho a todo vapor",
                    icon: Flame,
                    color: "orange",
                  },
                  {
                    label: "Aguardando pagamento",
                    value: orders.filter((o) => o.status === "pending_payment")
                      .length,
                    detail: "Ainda fora da cozinha",
                    icon: Clock3,
                    color: "purple",
                  },
                ].map(({ label, value, detail, icon: Icon, color }) => (
                  <article className="stat-card" key={label}>
                    <div>
                      <span>{label}</span>
                      <span className={`stat-icon ${color}`}>
                        <Icon size={18} />
                      </span>
                    </div>
                    <strong>{value}</strong>
                    <small>{detail}</small>
                  </article>
                ))}
              </section>
              <div className="dashboard-grid">
                <section className="panel">
                  <div className="panel-title">
                    <div>
                      <h2>
                        Pedidos recentes{" "}
                        <span className="count">{orders.length}</span>
                      </h2>
                      <p>Os sabores que estão saindo por aqui.</p>
                    </div>
                    <button
                      className="text-button"
                      onClick={() => go("orders")}
                    >
                      Ver todos
                      <ArrowUpRight size={14} />
                    </button>
                  </div>
                  <OrderTable
                    orders={orders.slice(0, 5)}
                    onOpen={(o) => open({ type: "detail", order: o })}
                    onNew={() => open({ type: "order" })}
                  />
                </section>
                <section className="panel quick-menu">
                  <div className="panel-title">
                    <div>
                      <h2>As estrelas do cardápio</h2>
                      <p>Clássicos do nosso Planeta.</p>
                    </div>
                    <Sparkles size={17} />
                  </div>
                  {products
                    .filter((p) =>
                      ["x-tudo", "x-dogao", "coxinhas-50"].includes(p.id),
                    )
                    .map((p) => (
                      <div className="quick-product" key={p.id}>
                        <span>
                          {categories.find((c) => c.id === p.category).icon}
                        </span>
                        <div>
                          <strong>{p.name}</strong>
                          <small>
                            {categories.find((c) => c.id === p.category).name}
                          </small>
                        </div>
                        <b>{money(p.price)}</b>
                      </div>
                    ))}
                  <button className="menu-footer" onClick={() => go("menu")}>
                    Explorar o cardápio
                    <ArrowRight size={15} />
                  </button>
                </section>
              </div>
            </>
          )}
          {page === "menu" && (
            <MenuCatalog
              onNew={() => open({ type: "order" })}
              onSelect={(p) => open({ type: "order", product: p })}
            />
          )}
          {page === "orders" && (
            <Orders
              orders={orders}
              onOpen={(o) => open({ type: "detail", order: o })}
              onNew={() => open({ type: "order" })}
            />
          )}
          {page === "kitchen" && (
            <>
              <PageHeading
                kicker="COZINHA"
                title="Capricho em cada pedido."
                description="Aqui entram apenas pedidos com pagamento confirmado."
              />
              <div className="kitchen-grid">
                {["queued", "preparing", "ready"].map((status) => (
                  <section className="kitchen-column" key={status}>
                    <div className="column-title">
                      <Badge status={status} />
                      <span>
                        {
                          orders.filter((o) => o.status === status && o.paid)
                            .length
                        }
                      </span>
                    </div>
                    {orders
                      .filter((o) => o.status === status && o.paid)
                      .map((o) => (
                        <article className="kitchen-card" key={o.id}>
                          <div className="row-between">
                            <b>#{String(o.id).padStart(4, "0")}</b>
                            <small>
                              {new Date(o.created * 1000).toLocaleTimeString(
                                "pt-BR",
                                { hour: "2-digit", minute: "2-digit" },
                              )}
                            </small>
                          </div>
                          <h3>{o.customer}</h3>
                          <span className="channel">
                            {o.channel === "counter" ? "Balcão" : "WhatsApp"}
                          </span>
                          <ul>
                            {o.items.map((i, index) => (
                              <li key={index}>
                                <b>{i.qty}×</b>
                                {i.name}
                              </li>
                            ))}
                          </ul>
                          {o.notes && <p className="notes">{o.notes}</p>}
                          <button
                            className="primary full"
                            disabled={busy}
                            onClick={() =>
                              mutate(
                                "orders/status",
                                { id: o.id, status: nextStatus[status] },
                                "Etapa atualizada.",
                              )
                            }
                          >
                            {nextLabel[status]}
                            <ArrowRight size={15} />
                          </button>
                        </article>
                      ))}
                    {!orders.some((o) => o.status === status && o.paid) && (
                      <div className="column-empty">
                        <ChefHat size={28} />
                        <p>
                          Nenhum pedido nesta etapa.
                          <br />
                          Tudo em ordem por aqui.
                        </p>
                      </div>
                    )}
                  </section>
                ))}
              </div>
            </>
          )}
          {page === "team" && admin && (
            <>
              <PageHeading
                kicker="GESTÃO"
                title="Gente que faz acontecer."
                description="Acesso individual, com as permissões certas para cada função."
                action={
                  <button
                    className="primary"
                    onClick={() => open({ type: "user" })}
                  >
                    <Plus size={17} />
                    Adicionar funcionário
                  </button>
                }
              />
              <div className="role-grid">
                {[
                  {
                    name: "Administrador",
                    icon: ShieldCheck,
                    desc: "Visão geral, pedidos, cozinha, pagamentos e gestão da equipe.",
                  },
                  {
                    name: "Funcionário",
                    icon: ChefHat,
                    desc: "Cadastro e acompanhamento de pedidos e etapas da cozinha. Sem acesso à gestão ou confirmação de pagamentos.",
                  },
                ].map(({ name, icon: Icon, desc }) => (
                  <article className="panel role-panel" key={name}>
                    <Icon />
                    <h2>{name}</h2>
                    <p>{desc}</p>
                  </article>
                ))}
              </div>
              <section className="panel">
                <div className="panel-title">
                  <h2>
                    Sua equipe <span className="count">{team.length}</span>
                  </h2>
                </div>
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Pessoa</th>
                        <th>Usuário</th>
                        <th>Perfil</th>
                        <th>Acesso</th>
                        <th />
                      </tr>
                    </thead>
                    <tbody>
                      {team.map((u) => (
                        <tr key={u.id}>
                          <td>
                            <strong>{u.name}</strong>
                          </td>
                          <td>{u.username}</td>
                          <td>
                            {u.role === "admin"
                              ? "Administrador"
                              : "Funcionário"}
                          </td>
                          <td>
                            <span
                              className={`badge ${u.active ? "ready" : "cancelled"}`}
                            >
                              {u.active ? "Ativo" : "Bloqueado"}
                            </span>
                          </td>
                          <td>
                            {u.role === "employee" && (
                              <button
                                className="text-button"
                                disabled={busy}
                                onClick={() => {
                                  if (
                                    confirm(
                                      `Deseja ${u.active ? "bloquear" : "reativar"} o acesso de ${u.name}? As sessões serão encerradas.`,
                                    )
                                  )
                                    mutate(
                                      "users/toggle",
                                      { id: u.id },
                                      "Acesso atualizado.",
                                    );
                                }}
                              >
                                {u.active ? "Bloquear" : "Reativar"}
                              </button>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </section>
            </>
          )}
          {page === "settings" && admin && (
            <>
              <PageHeading
                kicker="GESTÃO"
                title="Seu Planeta, conectado."
                description="As próximas conexões para simplificar a operação."
              />
              <div className="role-grid">
                {[
                  {
                    icon: Wallet,
                    title: "Confirmação automática de Pix",
                    desc: "Nesta versão, o administrador confere o recebimento e confirma manualmente no pedido.",
                  },
                  {
                    icon: Phone,
                    title: "Pedidos pelo WhatsApp",
                    desc: "Por enquanto, a equipe cadastra os pedidos recebidos no WhatsApp e identifica o canal.",
                  },
                  {
                    icon: CheckCheck,
                    title: "Impressão automática",
                    desc: "A integração depende da impressora e do computador utilizados na loja.",
                  },
                ].map(({ icon: Icon, title, desc }) => (
                  <article className="panel role-panel" key={title}>
                    <Icon />
                    <h2>{title}</h2>
                    <span className="badge pending_payment">Não conectada</span>
                    <p>{desc}</p>
                  </article>
                ))}
              </div>
            </>
          )}
        </main>
        <footer>
          <Brand />
          <span>Sabor que te leva mais longe.</span>
          <small>
            Carpina · PE <span>✦</span> Feito com amor
          </small>
        </footer>
      </div>
      <dialog
        ref={dialogRef}
        onCancel={() => setModal(null)}
        onClose={() => setModal(null)}
      >
        <button
          className="modal-close icon-button"
          aria-label="Fechar"
          onClick={() => setModal(null)}
        >
          <X size={21} />
        </button>
        {modal?.type === "order" && (
          <NewOrder
            initialProduct={modal.product}
            busy={busy}
            error={error}
            onSubmit={(data) =>
              mutate(
                "orders",
                data,
                "Pedido criado. Aguardando confirmação do pagamento.",
              )
            }
          />
        )}{" "}
        {modal?.type === "user" && (
          <>
            <span className="section-kicker">EQUIPE</span>
            <h2>Novo funcionário</h2>
            <p className="muted">
              Login individual com acesso aos pedidos e à cozinha.
            </p>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                mutate(
                  "users",
                  Object.fromEntries(new FormData(e.currentTarget)),
                  "Funcionário cadastrado.",
                );
              }}
            >
              <label>
                Nome
                <input name="name" required minLength={2} maxLength={80} />
              </label>
              <label>
                Usuário
                <input
                  name="username"
                  required
                  minLength={3}
                  maxLength={40}
                  pattern="[A-Za-z0-9._-]+"
                  autoComplete="off"
                />
              </label>
              <label>
                Senha inicial
                <input
                  name="password"
                  type="password"
                  required
                  minLength={10}
                  maxLength={256}
                  autoComplete="new-password"
                />
              </label>
              <p className="field-hint">
                Pelo menos 10 caracteres. Compartilhe por um canal seguro.
              </p>
              {error && (
                <p className="form-error" role="alert">
                  {error}
                </p>
              )}
              <button className="primary full" disabled={busy}>
                Cadastrar funcionário
                <Plus size={15} />
              </button>
            </form>
          </>
        )}
        {modal?.type === "detail" && (
          <OrderDetail
            order={modal.order}
            admin={admin}
            busy={busy}
            error={error}
            onMutate={mutate}
          />
        )}
      </dialog>
      {notice && (
        <div className="toast" role="status">
          <CircleHelp size={17} />
          {notice}
          <button
            aria-label="Dispensar aviso"
            className="icon-button"
            onClick={() => setNotice("")}
          >
            <X size={16} />
          </button>
        </div>
      )}
    </div>
  );
}
function PageHeading({ kicker, title, description, action }) {
  return (
    <div className="page-heading">
      <div>
        <span className="section-kicker">{kicker}</span>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      {action}
    </div>
  );
}
function Hero({ onClick, menu = false }) {
  return (
    <section className="hero-banner">
      <div className="hero-copy">
        <span className="eyebrow">
          <span /> DIRETO DO NOSSO PLANETA
        </span>
        <h2>
          {menu ? (
            <>
              Um universo de sabores.
              <br />
              <em>Feito para surpreender.</em>
            </>
          ) : (
            <>
              Sabor que te leva
              <br />
              <em>mais longe.</em>
            </>
          )}
        </h2>
        <p>
          {menu
            ? "Os clássicos da casa, do seu jeito. Do primeiro clique ao último detalhe."
            : "Da primeira mordida à última entrega. Sua operação com mais sabor e organização."}
        </p>
        <button onClick={onClick}>
          {menu ? "Montar um pedido" : "Explorar o cardápio"}
          <ArrowUpRight size={16} />
        </button>
      </div>
      <div className="hero-art">
        <img
          src="/brand/planeta-art.png"
          alt="Planeta Lanches: planeta roxo, hambúrguer, coxinha e batatas"
        />
      </div>
      <div className="hero-stars" aria-hidden="true">
        ✦
      </div>
    </section>
  );
}
function MenuCatalog({ onNew, onSelect }) {
  const [category, setCategory] = useState("all");
  const [query, setQuery] = useState("");
  const filtered = products.filter(
    (p) =>
      (category === "all" || p.category === category) &&
      normalize(p.name + " " + p.description).includes(normalize(query)),
  );
  return (
    <>
      <PageHeading
        kicker="CARDÁPIO DA CASA"
        title="Qual vai ser o sabor de hoje?"
        description="Os favoritos do Planeta Lanches, todos em um só lugar."
        action={
          <button className="primary" onClick={onNew}>
            <Plus size={17} />
            Novo pedido
          </button>
        }
      />
      <Hero menu onClick={onNew} />
      <div className="menu-summary">
        <span>
          <span className="live-dot" />
          <b>{products.length}</b> produtos no cardápio
        </span>
        <span>
          <UtensilsCrossed size={14} />7 categorias para explorar
        </span>
        <span className="menu-source">
          <Check size={14} />
          Preços do cardápio da loja
        </span>
      </div>
      <div className="catalog-controls">
        <div
          className="category-tabs"
          role="group"
          aria-label="Categorias do cardápio"
        >
          {categories.map((c) => (
            <button
              key={c.id}
              className={category === c.id ? "active" : ""}
              onClick={() => setCategory(c.id)}
            >
              <span>{c.icon}</span>
              {c.id === "all" ? "Todos" : c.name}
              {category === c.id && (
                <span className="category-count">
                  {
                    products.filter(
                      (p) => c.id === "all" || p.category === c.id,
                    ).length
                  }
                </span>
              )}
            </button>
          ))}
        </div>
        <label className="search-box">
          <Search size={17} />
          <input
            aria-label="Buscar no cardápio"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Buscar produto ou ingrediente…"
          />
          {query && (
            <button aria-label="Limpar busca" onClick={() => setQuery("")}>
              <X size={14} />
            </button>
          )}
        </label>
      </div>
      <div className="catalog-heading">
        <h2>
          {query
            ? "Resultados da busca"
            : categories.find((c) => c.id === category).name}
          <span className="count">{filtered.length}</span>
        </h2>
        <span>
          <SlidersHorizontal size={14} /> Ordem do cardápio
        </span>
      </div>
      <div className="product-grid">
        {filtered.map((p) => (
          <ProductCard key={p.id} product={p} onSelect={onSelect} />
        ))}
      </div>
      {!filtered.length && (
        <div className="empty">
          <Search size={30} />
          <h3>Nenhum sabor por aqui.</h3>
          <p>Tente outro nome ou ingrediente.</p>
          <button
            className="text-button"
            onClick={() => {
              setQuery("");
              setCategory("all");
            }}
          >
            Limpar filtros
          </button>
        </div>
      )}
      <div className="catalog-footnote">
        <CircleHelp size={14} />
        <span>
          Valores do cardápio da loja. Santa Joana e Antarctica 200 ml
          confirmados pela equipe.
        </span>
      </div>
    </>
  );
}
function ProductCard({ product: p, onSelect }) {
  const c = categories.find((c) => c.id === p.category);
  return (
    <article className={`product-card product-${p.category}`}>
      <div className="product-top">
        <span className="product-illustration" aria-hidden="true">
          {c.icon}
        </span>
        <span className="product-category">{c.name}</span>
        {["x-tudo", "x-dogao"].includes(p.id) && (
          <span className="special-tag">
            <Sparkles size={10} />
            Especial
          </span>
        )}
      </div>
      <h3>{p.name}</h3>
      <p>{p.description || "Uma bebida para acompanhar seu lanche."}</p>
      <div className="product-bottom">
        <strong>{money(p.price)}</strong>
        <button
          aria-label={`Adicionar ${p.name} ao pedido`}
          title="Adicionar ao pedido"
          onClick={() => onSelect(p)}
        >
          <Plus size={19} />
        </button>
      </div>
    </article>
  );
}
function OrderTable({ orders, onOpen, onNew }) {
  return orders.length ? (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Pedido / cliente</th>
            <th>Canal</th>
            <th>Status</th>
            <th>Total</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {orders.map((o) => (
            <tr key={o.id}>
              <td>
                <button className="order-link" onClick={() => onOpen(o)}>
                  <strong>#{String(o.id).padStart(4, "0")}</strong>
                  <span>{o.customer}</span>
                </button>
              </td>
              <td>
                <span className="channel">
                  {o.channel === "counter" ? "Balcão" : "WhatsApp"}
                </span>
              </td>
              <td>
                <Badge status={o.status} />
              </td>
              <td>
                <strong>{money(o.total)}</strong>
              </td>
              <td>
                <button
                  className="icon-button"
                  aria-label={`Abrir pedido ${o.id}`}
                  onClick={() => onOpen(o)}
                >
                  <ArrowUpRight size={17} />
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  ) : (
    <div className="empty">
      <ShoppingBasket size={32} />
      <h3>Seu próximo pedido começa aqui.</h3>
      <p>Cadastre um pedido e acompanhe cada etapa.</p>
      <button className="secondary" onClick={onNew}>
        <Plus size={15} />
        Criar primeiro pedido
      </button>
    </div>
  );
}
function Orders({ orders, onOpen, onNew }) {
  const [filter, setFilter] = useState("all");
  const [search, setSearch] = useState("");
  const filtered = orders.filter(
    (o) =>
      (filter === "all" || o.status === filter) &&
      normalize(o.id + " " + o.customer).includes(normalize(search)),
  );
  return (
    <>
      <PageHeading
        kicker="ATENDIMENTO"
        title="Cada pedido no seu lugar."
        description="Do balcão e do WhatsApp, com todas as etapas à vista."
        action={
          <button className="primary" onClick={onNew}>
            <Plus size={17} />
            Novo pedido
          </button>
        }
      />
      <section className="panel">
        <div className="order-toolbar">
          <div className="order-tabs">
            {["all", ...Object.keys(labels)].map((s) => (
              <button
                key={s}
                className={filter === s ? "active" : ""}
                onClick={() => setFilter(s)}
              >
                {s === "all" ? "Todos" : labels[s]}
                <span>
                  {orders.filter((o) => s === "all" || o.status === s).length}
                </span>
              </button>
            ))}
          </div>
          <label className="search-box">
            <Search size={15} />
            <input
              aria-label="Buscar pedido ou cliente"
              placeholder="Buscar pedido ou cliente…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </label>
        </div>
        <OrderTable orders={filtered} onOpen={onOpen} onNew={onNew} />
      </section>
      <p className="catalog-footnote">
        <Clock3 size={14} />
        Atualizado a cada 15 segundos. Pedidos só entram na cozinha após a
        confirmação do pagamento.
      </p>
    </>
  );
}
function NewOrder({ initialProduct, busy, error, onSubmit }) {
  const [items, setItems] = useState(
    initialProduct ? [{ ...initialProduct, qty: 1 }] : [],
  );
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("all");
  const filtered = products.filter(
    (p) =>
      (category === "all" || p.category === category) &&
      normalize(p.name).includes(normalize(query)),
  );
  function add(p) {
    setItems((prev) => {
      const found = prev.find((i) => i.id === p.id);
      return found
        ? prev.map((i) =>
            i.id === p.id ? { ...i, qty: Math.min(100, i.qty + 1) } : i,
          )
        : prev.length < 30
          ? [...prev, { ...p, qty: 1 }]
          : prev;
    });
  }
  function change(id, amount) {
    setItems((prev) =>
      prev
        .map((i) =>
          i.id === id ? { ...i, qty: Math.min(100, i.qty + amount) } : i,
        )
        .filter((i) => i.qty > 0),
    );
  }
  return (
    <>
      <span className="section-kicker">ATENDIMENTO</span>
      <h2>Vamos montar esse pedido?</h2>
      <p className="muted">Escolha os produtos e adicionais do cardápio.</p>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (!items.length) return;
          onSubmit({
            ...Object.fromEntries(new FormData(e.currentTarget)),
            items: items.map((i) => ({
              name: i.name,
              qty: i.qty,
              price: i.price,
            })),
          });
        }}
      >
        <label>
          Cliente
          <input
            name="customer"
            required
            maxLength={100}
            placeholder="Nome ou identificação da mesa"
          />
        </label>
        <div className="form-grid">
          <label>
            Canal
            <select name="channel">
              <option value="counter">Balcão</option>
              <option value="whatsapp">WhatsApp · cadastro manual</option>
            </select>
          </label>
          <label>
            Pagamento
            <select name="payment">
              <option value="pix">Pix</option>
              <option value="cash">Dinheiro</option>
              <option value="card">Cartão</option>
            </select>
          </label>
        </div>
        <div className="picker-controls">
          <input
            aria-label="Buscar produto para o pedido"
            placeholder="Buscar produto…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <select
            aria-label="Categoria do produto"
            value={category}
            onChange={(e) => setCategory(e.target.value)}
          >
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </div>
        <div className="product-picker">
          {filtered.map((p) => (
            <button key={p.id} type="button" onClick={() => add(p)}>
              <span>{p.name}</span>
              <strong>{money(p.price)}</strong>
              <Plus size={14} />
            </button>
          ))}
          {!filtered.length && <p>Nenhum produto encontrado.</p>}
        </div>
        <div className="cart-title">
          <ShoppingBag size={15} />
          Seu pedido <span>{items.reduce((a, i) => a + i.qty, 0)} itens</span>
        </div>
        {items.map((i) => (
          <div className="cart-item" key={i.id}>
            <div>
              <strong>{i.name}</strong>
              <small>{money(i.price)} por item</small>
            </div>
            <div className="qty-control">
              <button
                type="button"
                aria-label={`Diminuir ${i.name}`}
                onClick={() => change(i.id, -1)}
              >
                <Minus size={13} />
              </button>
              <span>{i.qty}</span>
              <button
                type="button"
                aria-label={`Aumentar ${i.name}`}
                onClick={() => change(i.id, 1)}
              >
                <Plus size={13} />
              </button>
            </div>
            <b>{money(i.price * i.qty)}</b>
          </div>
        ))}
        {!items.length && (
          <p className="field-hint">
            Adicione pelo menos um produto para continuar.
          </p>
        )}
        <label>
          Observações
          <textarea
            name="notes"
            maxLength={1000}
            placeholder="Sem cebola, adicionais no X-Tudo…"
          />
        </label>
        <p className="field-hint">
          Os adicionais aparecem como itens separados. Indique nas observações a
          qual lanche pertencem.
        </p>
        <div className="total-row">
          <span>Total do pedido</span>
          <strong>
            {money(items.reduce((a, i) => a + i.qty * i.price, 0))}
          </strong>
        </div>
        <div className="info-box">
          <ShieldCheck size={16} />
          <span>
            O pedido aguarda confirmação do pagamento antes de ir à cozinha.
          </span>
        </div>
        {error && (
          <p role="alert" className="form-error">
            {error}
          </p>
        )}
        <button className="primary full" disabled={busy || !items.length}>
          {busy ? "Criando…" : "Criar pedido"}
          <ArrowRight size={16} />
        </button>
      </form>
    </>
  );
}
function OrderDetail({ order: o, admin, busy, error, onMutate }) {
  return (
    <>
      <span className="section-kicker">
        PEDIDO #{String(o.id).padStart(4, "0")}
      </span>
      <h2>{o.customer}</h2>
      <Badge status={o.status} />
      <p className="muted detail-date">
        {o.channel === "counter" ? "Balcão" : "WhatsApp"} ·{" "}
        {new Date(o.created * 1000).toLocaleString("pt-BR")}
      </p>
      <div className="detail-items">
        {o.items.map((i, index) => (
          <div key={index}>
            <span>
              <b>{i.qty}×</b> {i.name}
            </span>
            <strong>{money(i.qty * i.price)}</strong>
          </div>
        ))}
      </div>
      {o.notes && <p className="notes">{o.notes}</p>}
      <div className="total-row">
        <span>Total</span>
        <strong>{money(o.total)}</strong>
      </div>
      <p className="muted">
        {{ pix: "Pix", cash: "Dinheiro", card: "Cartão" }[o.payment]} ·{" "}
        {o.paid ? "Confirmado manualmente" : "Pagamento pendente"}
      </p>
      {o.status === "pending_payment" && admin && (
        <>
          <div className="info-box">
            <Banknote size={17} />
            <span>
              Confira o recebimento antes de confirmar. Esta ação é manual.
            </span>
          </div>
          <button
            className="primary full"
            disabled={busy}
            onClick={() =>
              onMutate(
                "orders/payment",
                { id: o.id },
                "Pagamento confirmado. Pedido liberado para a cozinha.",
              )
            }
          >
            <Check size={16} />
            Conferi o pagamento · liberar pedido
          </button>
        </>
      )}
      {nextStatus[o.status] && (
        <button
          className="primary full detail-advance"
          disabled={busy}
          onClick={() =>
            onMutate(
              "orders/status",
              { id: o.id, status: nextStatus[o.status] },
              "Pedido atualizado.",
            )
          }
        >
          {nextLabel[o.status]}
          <ArrowRight size={15} />
        </button>
      )}
      {admin && !["cancelled", "completed"].includes(o.status) && (
        <button
          className="danger-text"
          disabled={busy}
          onClick={() => {
            if (
              confirm(
                `Cancelar pedido #${o.id}? ${o.paid ? "Esta ação não realiza estorno." : ""}`,
              )
            )
              onMutate(
                "orders/status",
                { id: o.id, status: "cancelled" },
                "Pedido cancelado.",
              );
          }}
        >
          Cancelar pedido
        </button>
      )}
      {error && (
        <p role="alert" className="form-error">
          {error}
        </p>
      )}
    </>
  );
}
export default App;
