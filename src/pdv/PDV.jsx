import { useCallback, useEffect, useState } from "react";
import {
  Plus,
  Minus,
  Trash2,
  Search,
  ShoppingBasket,
  ArrowRight,
  LockKeyhole,
  WifiOff,
  Check,
  RotateCcw,
  Banknote,
  Smartphone,
  CreditCard,
  Clock3,
} from "lucide-react";
import { QRCodeSVG } from "qrcode.react";
import sourceMenu from "../data/menu.json";
import { useAuth } from "../auth/context";
import { supabase, rpc } from "../lib/supabase";
import {
  money,
  normalize,
  cents,
  toggleModifier,
  emptyDraft,
  orderPayload,
} from "../lib/operations";
import { useConnection } from "../components/useConnection";
import { reportError } from "../lib/monitoring";
import ErrorBoundary from "../components/ErrorBoundary";
import CashDrawer from "./CashDrawer";
const categories = [
  ["all", "Todos"],
  ["hamburgueres", "Hambúrgueres"],
  ["dogoes", "Dogões"],
  ["combos", "Combos"],
  ["porcoes", "Porções"],
  ["pasteis", "Pastéis"],
  ["coxinhas", "Mini coxinhas"],
  ["bebidas", "Bebidas"],
  ["adicionais", "Adicionais"],
];
const previewProducts = sourceMenu.map((p) => ({
  ...p,
  price_cents: p.price,
  image_path: `/menu/${p.category}.svg`,
  allowed_modifiers:
    p.category === "hamburgueres"
      ? [
          "Sem cebola",
          "Sem tomate",
          "Sem alface",
          "Sem molhos",
          "Ponto: mal passado",
          "Ponto: ao ponto",
          "Ponto: bem passado",
        ]
      : p.category === "dogoes"
        ? ["Sem cebola", "Sem molhos"]
        : [],
}));
function restore(user) {
  try {
    return (
      JSON.parse(sessionStorage.getItem(`planeta:pdv:${user}`)) || emptyDraft()
    );
  } catch {
    return emptyDraft();
  }
}
export default function PDV({ preview = false }) {
  const { profile, locked, unlock } = useAuth();
  const online = useConnection();
  const [products, setProducts] = useState(preview ? previewProducts : []),
    [catalogError, setCatalogError] = useState("");
  const [draft, setDraft] = useState(() =>
    restore(preview ? "preview" : profile.id),
  );
  const [selected, setSelected] = useState(null),
    [category, setCategory] = useState("all"),
    [query, setQuery] = useState("");
  const [shift, setShift] = useState(null),
    [loadingShift, setLoadingShift] = useState(!preview),
    [shiftValue, setShiftValue] = useState("0,00");
  const [method, setMethod] = useState(() => draft.payment?.method || "cash"),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [pin, setPin] = useState(""),
    [closing, setClosing] = useState(false);
  const [closingReason, setClosingReason] = useState("");
  const [paymentIntent, setPaymentIntent] = useState(null);
  const [pendingOrders, setPendingOrders] = useState(null);
  const userId = preview ? "preview" : profile.id;
  const profileId = profile?.id;
  useEffect(() => {
    try {
      sessionStorage.setItem(`planeta:pdv:${userId}`, JSON.stringify(draft));
    } catch {
      /* A full device disk must not crash the cashier. */
    }
  }, [draft, userId]);
  const load = useCallback(async () => {
    if (preview || locked) return;
    setCatalogError("");
    setLoadingShift(true);
    try {
      const [catalog, turns] = await Promise.all([
        supabase
          .from("products")
          .select(
            "id,name,category,description,price_cents,image_path,allowed_modifiers",
          )
          .eq("active", true)
          .order("category")
          .order("price_cents"),
        supabase
          .from("shifts")
          .select("id,opened_at,opening_cents")
          .eq("cashier_id", profileId)
          .is("closed_at", null)
          .maybeSingle(),
      ]);
      if (catalog.error || turns.error)
        throw new Error("Não foi possível sincronizar produtos e caixa.");
      setProducts(catalog.data);
      setShift(turns.data);
    } catch (e) {
      setCatalogError(e.message);
      reportError(e, "catalog");
    } finally {
      setLoadingShift(false);
    }
  }, [preview, locked, profileId]);
  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, [load]);
  const frozen = busy || draft.submitted || Boolean(draft.order);
  const estimate = draft.items.reduce(
    (sum, i) => sum + i.price_cents * i.quantity,
    0,
  );
  const total = draft.order?.total_cents ?? estimate;
  const filtered = products.filter(
    (p) =>
      (category === "all" || p.category === category) &&
      normalize(p.name + " " + p.description).includes(normalize(query)),
  );
  function add(product) {
    if (frozen) return;
    const found = draft.items.find(
      (i) => i.id === product.id && !i.modifiers.length && !i.notes,
    );
    if (!found && draft.items.length >= 30) {
      setError("Limite de 30 linhas por pedido.");
      return;
    }
    const line = found
      ? { ...found, quantity: Math.min(100, found.quantity + 1) }
      : {
          ...product,
          lineId: crypto.randomUUID(),
          quantity: 1,
          modifiers: [],
          notes: "",
        };
    setDraft({
      ...draft,
      items: found
        ? draft.items.map((i) => (i.lineId === line.lineId ? line : i))
        : [...draft.items, line],
    });
    setSelected(line.lineId);
    setError("");
    if (window.innerWidth <= 740)
      setTimeout(
        () =>
          document
            .getElementById("pedido-atual")
            ?.scrollIntoView({ behavior: "smooth", block: "start" }),
        0,
      );
  }
  function update(lineId, change) {
    if (frozen) return;
    setDraft({
      ...draft,
      items: draft.items
        .map((i) => (i.lineId === lineId ? { ...i, ...change } : i))
        .filter((i) => i.quantity > 0),
    });
  }
  function reset() {
    if (draft.submitted && !draft.order) {
      setError(
        "Reenvie a mesma tentativa antes de iniciar outro pedido. O servidor pode já ter recebido este pedido.",
      );
      return;
    }
    setDraft(emptyDraft());
    setSelected(null);
    setPaymentIntent(null);
    setError("");
  }
  async function send() {
    if (preview || !online || busy || !draft.items.length || locked) return;
    setBusy(true);
    setError("");
    const sending = { ...draft, submitted: true };
    setDraft(sending);
    try {
      sessionStorage.setItem(`planeta:pdv:${userId}`, JSON.stringify(sending));
    } catch {
      /* Memory draft remains usable if browser storage is full. */
    }
    try {
      const order = await rpc("create_order", orderPayload(sending));
      setDraft((prev) => ({ ...prev, order, submitted: false }));
    } catch (e) {
      if (e.rejected) {
        setDraft((prev) => ({ ...prev, submitted: false }));
        setError(e.message);
      } else
        setError(
          e.message +
            " O pedido foi preservado: use “Reenviar mesma tentativa”.",
        );
      reportError(e, "create_order");
    } finally {
      setBusy(false);
    }
  }
  async function pay() {
    if (preview || !online || busy || !draft.order || locked) return;
    setBusy(true);
    setError("");
    const payment = draft.payment || { method, key: draft.paymentKeys[method] };
    setDraft((prev) => ({ ...prev, payment }));
    try {
      if (payment.method === "cash") {
        const attempt = await rpc("begin_payment", {
          p_order: draft.order.id,
          p_method: "cash",
          p_key: payment.key,
        });
        await rpc("confirm_cash", { p_attempt: attempt.id });
        setDraft((prev) => ({
          ...prev,
          order: { ...prev.order, status: "queued" },
          payment: { ...payment, status: "confirmed" },
        }));
      } else {
        const { data, error: failure } = await supabase.functions.invoke(
          "payment-intent",
          {
            body: {
              orderId: draft.order.id,
              method: payment.method,
              key: payment.key,
            },
          },
        );
        if (failure) {
          let message =
            "Serviço de pagamento indisponível. Tente novamente com a mesma tentativa.";
          try {
            const body = await failure.context.json();
            message = body.error || message;
            if (failure.context.status === 503)
              setDraft((prev) => ({ ...prev, payment: null }));
          } catch {
            /* Preserve attempt when the response cannot be read. */
          }
          throw new Error(message);
        }
        setPaymentIntent(data);
      }
    } catch (e) {
      setError(e.message);
      reportError(e, "payment");
    } finally {
      setBusy(false);
    }
  }
  useEffect(() => {
    if (
      preview ||
      !draft.order ||
      draft.payment?.status === "confirmed" ||
      draft.order.status === "cancelled" ||
      locked
    )
      return;
    let stopped = false;
    const check = async () => {
      const { data } = await supabase
        .from("orders")
        .select("id,status,total_cents")
        .eq("id", draft.order.id)
        .maybeSingle();
      if (
        !stopped &&
        data &&
        ["queued", "preparing", "ready", "completed"].includes(data.status)
      )
        setDraft((prev) => ({
          ...prev,
          order: { ...prev.order, ...data },
          payment: { ...prev.payment, status: "confirmed" },
        }));
      else if (!stopped && data?.status === "cancelled")
        setDraft((prev) => ({ ...prev, order: { ...prev.order, ...data } }));
    };
    const timer = setInterval(check, 4000);
    return () => {
      stopped = true;
      clearInterval(timer);
    };
  }, [preview, draft.order, draft.payment?.status, locked]);
  async function listPending() {
    setError("");
    const { data, error } = await supabase
      .from("orders")
      .select("id,number,customer,channel,total_cents,status,idempotency_key")
      .eq("cashier_id", profile.id)
      .eq("status", "pending_payment")
      .order("created_at");
    if (error) setError("Não foi possível consultar os pedidos pendentes.");
    else setPendingOrders(data);
  }
  async function resume(order) {
    if (
      draft.items.length &&
      draft.order?.id !== order.id &&
      !confirm(
        "Abrir este pedido? O rascunho atual será substituído. Pedidos já enviados permanecem no banco.",
      )
    )
      return;
    setBusy(true);
    setError("");
    try {
      const [lines, attempts] = await Promise.all([
        supabase
          .from("order_items")
          .select("product_id,name,quantity,unit_price_cents,modifiers,notes")
          .eq("order_id", order.id),
        supabase
          .from("payment_attempts")
          .select("id,method,status")
          .eq("order_id", order.id)
          .eq("status", "pending")
          .maybeSingle(),
      ]);
      if (lines.error || attempts.error)
        throw new Error("Não foi possível retomar o pedido.");
      const payment = attempts.data
        ? { method: attempts.data.method, key: attempts.data.id }
        : null;
      setDraft({
        ...emptyDraft(),
        key: order.idempotency_key,
        customer: order.customer,
        channel: order.channel,
        order,
        items: lines.data.map((i) => ({
          ...products.find((p) => p.id === i.product_id),
          id: i.product_id,
          name: i.name,
          price_cents: i.unit_price_cents,
          quantity: i.quantity,
          modifiers: i.modifiers,
          notes: i.notes,
          lineId: crypto.randomUUID(),
          allowed_modifiers:
            products.find((p) => p.id === i.product_id)?.allowed_modifiers ||
            [],
        })),
        payment,
      });
      setMethod(payment?.method || "cash");
      setPaymentIntent(null);
      setPendingOrders(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  async function cancelUnpaid() {
    if (!confirm("Cancelar este pedido ainda sem cobrança iniciada?")) return;
    setBusy(true);
    setError("");
    try {
      await rpc("cancel_unpaid_order", {
        p_order: draft.order.id,
        p_reason: prompt("Justificativa do cancelamento:") || "",
      });
      setDraft((prev) => ({
        ...prev,
        order: { ...prev.order, status: "cancelled" },
      }));
      setPendingOrders(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  async function shiftAction(event) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (closing) {
        await rpc("close_shift", {
          p_shift: shift.id,
          p_counted_cents: cents(shiftValue),
          p_reason: closingReason,
        });
        setClosing(false);
      } else await rpc("open_shift", { p_opening_cents: cents(shiftValue) });
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  if (!preview && locked)
    return (
      <section className="terminal-lock">
        <LockKeyhole size={34} />
        <span className="eyebrow">TERMINAL BLOQUEADO</span>
        <h1>Seu turno, com segurança.</h1>
        <p>{profile.name}, informe seu PIN para destravar este PDV.</p>
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            setError("");
            try {
              await unlock(pin);
              setPin("");
            } catch (e) {
              setError(e.message);
            } finally {
              setBusy(false);
            }
          }}
        >
          <label>
            PIN de 4 dígitos
            <input
              className="pin-input"
              aria-label="PIN de 4 dígitos"
              inputMode="numeric"
              type="password"
              pattern="[0-9]{4}"
              maxLength={4}
              minLength={4}
              required
              value={pin}
              autoComplete="off"
              onChange={(e) => setPin(e.target.value.replace(/\D/g, ""))}
            />
          </label>
          {error && (
            <p role="alert" className="error-message">
              {error}
            </p>
          )}
          <button className="primary full" disabled={busy || !online}>
            Destravar terminal
            <ArrowRight size={17} />
          </button>
        </form>
        <small>
          O PIN não substitui o login. Trocar de operador exige entrar com a
          conta da outra pessoa.
        </small>
      </section>
    );
  if (!preview && (loadingShift || (!shift && !catalogError)))
    return loadingShift ? (
      <div className="loading">Sincronizando caixa…</div>
    ) : (
      <section className="terminal-lock">
        <Banknote size={35} />
        <span className="eyebrow">COMEÇAR O TURNO</span>
        <h1>Vamos abrir seu caixa?</h1>
        <p>
          Informe o fundo de troco. Esse valor não altera o preço dos pedidos.
        </p>
        <form onSubmit={shiftAction}>
          <label>
            Fundo de troco (R$)
            <input
              inputMode="decimal"
              required
              value={shiftValue}
              onChange={(e) => setShiftValue(e.target.value)}
            />
          </label>
          {error && (
            <p role="alert" className="error-message">
              {error}
            </p>
          )}
          <button className="primary full" disabled={!online || busy}>
            Abrir meu caixa
            <ArrowRight size={17} />
          </button>
        </form>
      </section>
    );
  return (
    <>
      <div className="pdv-heading">
        <div>
          <span className="eyebrow">ATENDIMENTO ÁGIL · PLANETA LANCHES</span>
          <h1>
            Frente de caixa<span className="heading-dot">.</span>
          </h1>
          <p>Escolha, personalize e siga para o pagamento.</p>
        </div>
        <div className="shift-indicator">
          <span className="live-dot" />
          {preview
            ? "Prévia visual"
            : `Caixa de ${profile.name.split(" ")[0]}`}{" "}
          {!preview && (
            <button
              className="text-button"
              disabled={busy}
              onClick={() => {
                setClosing(!closing);
                setShiftValue("0,00");
              }}
            >
              Fechar caixa
            </button>
          )}
        </div>
      </div>
      {!preview && shift && <CashDrawer shiftId={shift.id} />}
      {closing && (
        <form className="close-shift" onSubmit={shiftAction}>
          <label>
            Dinheiro contado no fechamento (R$)
            <input
              inputMode="decimal"
              required
              value={shiftValue}
              onChange={(e) => setShiftValue(e.target.value)}
            />
          </label>
          <label>
            Justificativa do fechamento
            <input
              required
              minLength={5}
              maxLength={500}
              value={closingReason}
              onChange={(e) => setClosingReason(e.target.value)}
            />
          </label>
          <button
            className="secondary"
            type="button"
            onClick={() => setClosing(false)}
          >
            Voltar
          </button>
          <button className="primary" disabled={!online || busy}>
            Confirmar fechamento
          </button>
        </form>
      )}
      {catalogError && (
        <div className="error-message" role="alert">
          {catalogError}
          <button onClick={load} className="secondary">
            Tentar sincronizar
          </button>
        </div>
      )}
      {!preview && (
        <div className="pending-orders">
          <button
            className="text-button"
            disabled={busy || !online}
            onClick={listPending}
          >
            Consultar meus pedidos aguardando pagamento
            <ArrowRight size={13} />
          </button>
          {pendingOrders && (
            <div>
              {!pendingOrders.length && (
                <p>Nenhum pedido pendente neste caixa.</p>
              )}
              {pendingOrders.map((o) => (
                <button
                  className="secondary"
                  disabled={busy}
                  key={o.id}
                  onClick={() => resume(o)}
                >
                  #{o.number} · {o.customer} · {money(o.total_cents)}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
      {!online && (
        <div className="offline-banner" role="alert">
          <WifiOff size={18} />
          Sem internet. O rascunho está preservado neste terminal. Envios e
          pagamentos estão bloqueados.
        </div>
      )}
      <div className="pdv-layout">
        <section className="catalog" id="catalogo">
          <div className="catalog-top">
            <label className="search-box">
              <Search size={18} />
              <input
                aria-label="Buscar produto"
                placeholder="Buscar um sabor ou ingrediente…"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
              {query && (
                <button aria-label="Limpar busca" onClick={() => setQuery("")}>
                  <Trash2 size={14} />
                </button>
              )}
            </label>
            <span>{products.length} produtos no cardápio</span>
          </div>
          <div className="category-tabs" aria-label="Categorias">
            {categories.map(([id, name]) => (
              <button
                key={id}
                className={category === id ? "active" : ""}
                onClick={() => setCategory(id)}
              >
                {name}
                <span>
                  {id === "all"
                    ? products.length
                    : products.filter((p) => p.category === id).length}
                </span>
              </button>
            ))}
          </div>
          <div className="catalog-section-title">
            <h2>{categories.find(([id]) => id === category)[1]}</h2>
            <span>
              Seleção rápida <span>↗</span>
            </span>
          </div>
          <div className="product-grid">
            {filtered.map((p) => (
              <button
                className="product-card"
                key={p.id}
                disabled={frozen}
                onClick={() => add(p)}
                aria-label={`Adicionar ${p.name}`}
              >
                <div className="product-image">
                  <img
                    src={p.image_path}
                    alt={`Ilustração de ${p.name}`}
                    loading="lazy"
                  />
                  <span>ILUSTRAÇÃO</span>
                </div>
                <div className="product-info">
                  <small>
                    {categories.find(([id]) => id === p.category)?.[1]}
                  </small>
                  <h3>{p.name}</h3>
                  <p>{p.description || "Para acompanhar seu lanche."}</p>
                  <div>
                    <strong>{money(p.price_cents)}</strong>
                    <span className="add-square">
                      <Plus size={18} />
                    </span>
                  </div>
                </div>
              </button>
            ))}
          </div>
          {!filtered.length && (
            <div className="empty">
              <Search size={30} />
              <h2>
                {category === "combos"
                  ? "Seus combos entram aqui."
                  : "Nenhum produto encontrado."}
              </h2>
              <p>
                {category === "combos"
                  ? "Nenhum combo cadastrado. Os preços do cardápio original foram preservados."
                  : "Tente outro nome, ingrediente ou categoria."}
              </p>
            </div>
          )}
          <p className="catalog-note">
            Produtos e preços do cardápio da loja. Sem combos ou fichas técnicas
            inventadas.
          </p>
        </section>
        <aside className="checkout" id="pedido-atual">
          <button
            className="mobile-catalog-link text-button"
            onClick={() =>
              document
                .getElementById("catalogo")
                ?.scrollIntoView({ behavior: "smooth", block: "start" })
            }
          >
            ← Voltar ao cardápio
          </button>
          <div className="checkout-heading">
            <div>
              <ShoppingBasket size={19} />
              <h2>Pedido atual</h2>
            </div>
            <span>
              {draft.order
                ? `#${draft.order.number}`
                : `${draft.items.reduce((a, i) => a + i.quantity, 0)} itens`}
            </span>
          </div>
          <div className="customer-fields">
            <label>
              Cliente
              <input
                disabled={frozen}
                aria-label="Nome do cliente"
                placeholder="Cliente balcão"
                maxLength={100}
                value={draft.customer}
                onChange={(e) =>
                  setDraft({ ...draft, customer: e.target.value })
                }
              />
            </label>
            <label>
              Canal
              <select
                disabled={frozen}
                value={draft.channel}
                onChange={(e) =>
                  setDraft({ ...draft, channel: e.target.value })
                }
              >
                <option value="counter">Balcão</option>
                <option value="whatsapp">WhatsApp · manual</option>
              </select>
            </label>
          </div>
          <div className="cart-items">
            {!draft.items.length && (
              <div className="cart-empty">
                <ShoppingBasket size={38} />
                <h3>Qual vai ser o pedido?</h3>
                <p>
                  Toque nos produtos ao lado.
                  <br />
                  Os detalhes ficam aqui, sem complicação.
                </p>
              </div>
            )}
            {draft.items.map((item) => (
              <article
                className={`cart-line ${selected === item.lineId ? "selected" : ""}`}
                key={item.lineId}
              >
                <div className="cart-line-top">
                  <button
                    className="item-name"
                    aria-expanded={selected === item.lineId}
                    onClick={() =>
                      setSelected(selected === item.lineId ? null : item.lineId)
                    }
                  >
                    <strong>{item.name}</strong>
                    <small>
                      {item.modifiers.length
                        ? item.modifiers.join(" · ")
                        : "Toque para personalizar"}
                    </small>
                  </button>
                  <strong>{money(item.quantity * item.price_cents)}</strong>
                </div>
                <div className="cart-line-tools">
                  <div className="qty-control">
                    <button
                      aria-label={`Diminuir ${item.name}`}
                      disabled={frozen}
                      onClick={() =>
                        update(item.lineId, { quantity: item.quantity - 1 })
                      }
                    >
                      <Minus size={12} />
                    </button>
                    <b>{item.quantity}</b>
                    <button
                      aria-label={`Aumentar ${item.name}`}
                      disabled={frozen || item.quantity >= 100}
                      onClick={() =>
                        update(item.lineId, { quantity: item.quantity + 1 })
                      }
                    >
                      <Plus size={12} />
                    </button>
                  </div>
                  <button
                    className="icon-button"
                    aria-label={`Remover ${item.name}`}
                    disabled={frozen}
                    onClick={() => update(item.lineId, { quantity: 0 })}
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
                {selected === item.lineId && (
                  <ErrorBoundary area="modifiers">
                    <div className="inline-modifiers">
                      <span>DO JEITO DO CLIENTE</span>
                      <div>
                        {item.allowed_modifiers.map((m) => (
                          <button
                            key={m}
                            disabled={frozen}
                            className={
                              item.modifiers.includes(m) ? "active" : ""
                            }
                            onClick={() =>
                              update(item.lineId, {
                                modifiers: toggleModifier(item.modifiers, m),
                              })
                            }
                          >
                            {item.modifiers.includes(m) && <Check size={11} />}{" "}
                            {m}
                          </button>
                        ))}
                      </div>
                      <textarea
                        aria-label={`Observações de ${item.name}`}
                        placeholder="Algum detalhe para a cozinha?"
                        value={item.notes}
                        maxLength={500}
                        disabled={frozen}
                        onChange={(e) =>
                          update(item.lineId, { notes: e.target.value })
                        }
                      />
                    </div>
                  </ErrorBoundary>
                )}
              </article>
            ))}
          </div>
          <div className="checkout-bottom">
            <div className="subtotal">
              <span>
                {draft.order
                  ? "Total calculado no banco"
                  : "Total estimado · confirmado pelo banco"}
              </span>
              <strong>{money(total)}</strong>
            </div>
            {draft.order?.status === "cancelled" ? (
              <div className="error-message">
                <h3>Pedido cancelado.</h3>
                <p>Este pedido não está disponível para pagamento.</p>
                <button className="secondary" onClick={reset}>
                  Novo pedido
                </button>
              </div>
            ) : draft.payment?.status === "confirmed" ? (
              <div className="payment-success" role="status">
                <Check size={23} />
                <h3>Pagamento confirmado.</h3>
                <p>Pedido liberado para os setores da cozinha.</p>
                <button className="primary full" onClick={reset}>
                  Começar próximo pedido
                  <Plus size={16} />
                </button>
              </div>
            ) : draft.order ? (
              <>
                <div className="payment-options">
                  {[
                    ["cash", "Dinheiro", Banknote],
                    ["pix", "Pix", Smartphone],
                    ["tef", "Cartão", CreditCard],
                  ].map(([id, label, Icon]) => (
                    <button
                      key={id}
                      disabled={busy || Boolean(draft.payment)}
                      className={method === id ? "active" : ""}
                      onClick={() => setMethod(id)}
                    >
                      <Icon size={17} />
                      {label}
                    </button>
                  ))}
                </div>
                {method !== "cash" && (
                  <p className="payment-disclaimer">
                    Pix Nubank de conta física: confirmação manual do
                    administrador. TEF exige serviço homologado.
                  </p>
                )}
                {paymentIntent?.pix && (
                  <div className="pix-code">
                    <QRCodeSVG value={paymentIntent.pix.copyPaste} size={150} />
                    <p>
                      {paymentIntent.pix.expiresAt
                        ? `Válido até ${new Date(paymentIntent.pix.expiresAt).toLocaleTimeString("pt-BR")}`
                        : "QR Pix estático, sem expiração automática. Aguarde a conferência do crédito pelo administrador."}
                    </p>
                    <button
                      className="secondary"
                      onClick={() =>
                        navigator.clipboard.writeText(
                          paymentIntent.pix.copyPaste,
                        )
                      }
                    >
                      Copiar código Pix
                    </button>
                    <code>{paymentIntent.pix.copyPaste}</code>
                  </div>
                )}
                <button
                  className="primary full"
                  disabled={!online || busy || preview}
                  onClick={pay}
                >
                  {busy
                    ? "Processando…"
                    : draft.payment
                      ? "Retomar mesma tentativa"
                      : method === "cash"
                        ? "Confirmar recebimento em dinheiro"
                        : method === "pix"
                          ? "Gerar Pix com valor do pedido"
                          : "Iniciar TEF"}
                  <ArrowRight size={17} />
                </button>
                <p className="field-note">
                  <LockKeyhole size={12} />A cozinha só recebe após a
                  confirmação válida.
                </p>
              </>
            ) : (
              <>
                <button
                  className="primary full"
                  onClick={send}
                  disabled={!draft.items.length || busy || !online || preview}
                >
                  {busy
                    ? "Enviando…"
                    : draft.submitted
                      ? "Reenviar mesma tentativa"
                      : "Ir para pagamento"}
                  {draft.submitted ? (
                    <RotateCcw size={17} />
                  ) : (
                    <ArrowRight size={17} />
                  )}
                </button>
                <p className="field-note">
                  <Clock3 size={12} />
                  {preview
                    ? "Prévia sem banco. Pagamentos e envios desativados."
                    : "O banco valida produtos, quantidades e preços."}
                </p>
              </>
            )}
            {draft.order?.status === "pending_payment" && !draft.payment && (
              <button
                className="clear-cart"
                disabled={busy || !online}
                onClick={cancelUnpaid}
              >
                Cancelar pedido ainda sem cobrança
              </button>
            )}
            {error && (
              <p className="error-message" role="alert">
                {error}
              </p>
            )}
            {draft.items.length > 0 && !draft.order && !draft.submitted && (
              <button
                className="clear-cart"
                disabled={busy}
                onClick={() => {
                  if (confirm("Limpar o pedido em rascunho?")) reset();
                }}
              >
                Limpar rascunho
              </button>
            )}
          </div>
        </aside>
      </div>
      <button
        className="mobile-order-shortcut"
        onClick={() =>
          document
            .getElementById("pedido-atual")
            ?.scrollIntoView({ behavior: "smooth", block: "start" })
        }
      >
        <ShoppingBasket size={17} />
        <span>
          Ver pedido · {draft.items.reduce((sum, i) => sum + i.quantity, 0)}{" "}
          itens
        </span>
        <strong>{money(total)}</strong>
        <ArrowRight size={16} />
      </button>
    </>
  );
}
