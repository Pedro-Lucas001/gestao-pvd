import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { QRCodeSVG } from "qrcode.react";
import {
  ArrowLeft,
  ArrowRight,
  CheckCircle2,
  Clock,
  CreditCard,
  ShoppingBag,
  Truck,
} from "lucide-react";
import { cents, money } from "../lib/operations";
import { customerApi, configured } from "./customerApi";
import {
  useCart,
  cartPayload,
  draftLine,
  trackingToken,
  operationKey,
} from "./cart";
import CartEditor from "./CartEditor";
import CustomerChat from "./CustomerChat";
import "./PublicMenu.css";
import "./CustomerOrder.css";

const states = {
  payment_pending: "Pagamento pendente",
  awaiting_store: "Aguardando a confirmação da loja",
  accepted: "Na fila da cozinha",
  preparing: "Em preparo",
  ready: "Pedido pronto",
  dispatched: "Saiu para entrega",
  completed: "Pedido concluído",
  cancelled: "Pedido cancelado",
};
const pendingSlot = "planeta:online:pending";
function pendingRequest() {
  try {
    const p = JSON.parse(sessionStorage.getItem(pendingSlot) || "null");
    return p && /^[a-f0-9]{64}$/.test(p.tracking) && Array.isArray(p.items)
      ? p
      : null;
  } catch {
    return null;
  }
}
function forgetPending() {
  try {
    sessionStorage.removeItem(pendingSlot);
  } catch {
    /* Retry remains in memory. */
  }
}
function lastTracking() {
  try {
    return sessionStorage.getItem("planeta:online:last-tracking") || "";
  } catch {
    return "";
  }
}
function phoneNumber(value) {
  const n = value.replace(/\D/g, "");
  return n.length === 10 || n.length === 11 ? `55${n}` : n;
}
function Header() {
  return (
    <header className="menu-header customer-order-header">
      <Link className="menu-wordmark" to="/cardapio">
        <span>
          PLANETA <b>LANCHES</b>
          <small>Seu pedido, do seu jeito.</small>
        </span>
      </Link>
      <Link className="menu-staff-link" to="/cardapio">
        <ArrowLeft size={15} />
        Voltar ao cardápio
      </Link>
    </header>
  );
}

function Payment({ order, tracking }) {
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [artifact, setArtifact] = useState(null);
  const [key] = useState(() => operationKey());
  const payment = order.payments.find((p) => p.status === "pending");
  const pix = artifact?.pix || payment?.pix_code;
  const checkout = artifact?.url || payment?.checkout_url;
  const manual =
    artifact?.provider === "manual_pix" || payment?.provider === "manual_pix";
  async function generate() {
    setBusy(true);
    setError("");
    try {
      setArtifact(await customerApi("payment", { tracking, key }));
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  if (order.due_cents <= 0)
    return (
      <div className="customer-paid" role="status">
        <CheckCircle2 size={22} />
        <span>Pagamento confirmado pelo valor atual do pedido.</span>
      </div>
    );
  if (order.payment_method === "cash")
    return (
      <div className="customer-payment-note">
        <h3>Pagamento em dinheiro</h3>
        <p>
          Falta receber {money(order.due_cents)}. O recebimento será conferido
          pela equipe.
        </p>
        <p>
          {order.cash_change_for_cents
            ? `Troco solicitado para ${money(order.cash_change_for_cents)}${order.cash_change_for_cents >= order.due_cents ? `: ${money(order.cash_change_for_cents - order.due_cents)} de troco.` : ". O total mudou; combine um novo valor com a equipe."}`
            : "Sem necessidade de troco informada."}
        </p>
      </div>
    );
  return (
    <section className="customer-payment">
      <h3>
        {order.paid_cents > 0
          ? "Pagamento complementar"
          : "Finalize o pagamento"}
      </h3>
      <p className="customer-balance">{money(order.due_cents)}</p>
      <p>
        {order.paid_cents > 0
          ? "A cozinha aceitou a alteração. A diferença precisa ser confirmada para liberar o preparo revisado."
          : "O pedido só será liberado para preparo após a confirmação do pagamento."}
      </p>
      {!pix && !checkout && (
        <button
          type="button"
          className="customer-primary"
          disabled={busy}
          onClick={generate}
        >
          {busy
            ? "Preparando cobrança…"
            : order.payment_method === "pix"
              ? "Gerar Pix"
              : "Pagar com cartão em ambiente seguro"}
        </button>
      )}
      {pix && (
        <div className="customer-pix">
          <div className="customer-qr">
            <QRCodeSVG value={pix} size={185} />
          </div>
          <label>
            Pix copia e cola
            <textarea readOnly value={pix} onFocus={(e) => e.target.select()} />
          </label>
          <button
            type="button"
            className="customer-secondary"
            onClick={() =>
              navigator.clipboard
                ?.writeText(pix)
                .catch(() => setError("Selecione e copie o código Pix acima."))
            }
          >
            Copiar código Pix
          </button>
          <p>
            {manual
              ? "Pix sujeito à conferência da loja. Comprovante e captura de tela não confirmam o recebimento."
              : "Aguardando confirmação do provedor. Esta página acompanha o pagamento automaticamente."}
          </p>
        </div>
      )}
      {checkout &&
        /^https:\/\/(www\.|sandbox\.)?mercadopago\.(com\.br|com)\//.test(
          checkout,
        ) && (
          <a
            className="customer-primary"
            href={checkout}
            target="_blank"
            rel="noreferrer"
          >
            Abrir pagamento seguro
            <CreditCard size={18} />
          </a>
        )}
      {error && (
        <p role="alert" className="customer-error">
          {error}
        </p>
      )}
    </section>
  );
}
function ChangeRequest({ order, tracking, catalog, onDone }) {
  const [items, setItems] = useState(() =>
    order.items.map((i) =>
      draftLine({ ...i, price_cents: i.unit_price_cents }, i.quantity),
    ),
  );
  const [reason, setReason] = useState(""),
    [quote, setQuote] = useState(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const [key] = useState(() => operationKey());
  const [submission, setSubmission] = useState(null);
  useEffect(() => {
    if (!items.length) return;
    const controller = new AbortController();
    const timer = setTimeout(() => {
      setQuote(null);
      customerApi(
        "quote",
        { tracking, items: cartPayload(items), fulfillment: order.fulfillment },
        controller.signal,
      )
        .then(setQuote)
        .catch((e) => {
          if (!controller.signal.aborted) setError(e.message);
        });
    }, 250);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [items, tracking, order.fulfillment]);
  async function submit(event) {
    event.preventDefault();
    if ((!quote && !submission) || busy) return;
    const request = submission || {
      tracking,
      key,
      items: cartPayload(items),
      reason,
      expected_total_cents: quote.total_cents,
    };
    setSubmission(request);
    setBusy(true);
    setError("");
    try {
      await customerApi("change", request);
      onDone();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <form className="customer-change-form" onSubmit={submit}>
      <h3>Solicitar alteração à cozinha</h3>
      <p>
        Revise quantidades, itens e personalizações. Nada muda no preparo até a
        aprovação dos setores envolvidos. Se houver valor adicional, o pedido
        revisado aguardará o pagamento. Um pedido inteiro não pode ser cancelado
        por este formulário; fale com a equipe.
      </p>
      <CartEditor
        items={items}
        setItems={setItems}
        catalog={catalog}
        disabled={Boolean(submission)}
        allowAdd
      />
      <label>
        Explique o que deseja alterar
        <textarea
          required
          minLength={3}
          maxLength={500}
          disabled={Boolean(submission)}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="Ex.: retirar cebola e acrescentar uma porção de batata."
        />
      </label>
      {quote && (
        <div className="customer-summary">
          <span>
            Novo total<strong>{money(quote.total_cents)}</strong>
          </span>
          <span>
            Já recebido<strong>{money(order.paid_cents)}</strong>
          </span>
          <span>
            {quote.total_cents >= order.paid_cents
              ? "Diferença pendente após aprovação"
              : "Valor a devolver após aprovação"}
            <strong>
              {money(Math.abs(quote.total_cents - order.paid_cents))}
            </strong>
          </span>
        </div>
      )}
      {error && (
        <p role="alert" className="customer-error">
          {error}
        </p>
      )}
      <button
        className="customer-primary"
        disabled={busy || !items.length || (!quote && !submission)}
      >
        {busy
          ? "Enviando…"
          : submission
            ? "Retomar mesma solicitação"
            : "Enviar solicitação para análise"}
      </button>
    </form>
  );
}
function Tracker({ tracking, shop, catalog, onNew }) {
  const [order, setOrder] = useState(null),
    [error, setError] = useState(""),
    [change, setChange] = useState(false),
    [version, setVersion] = useState(0),
    [notice, setNotice] = useState("");
  useEffect(() => {
    const c = new AbortController();
    async function load() {
      try {
        const result = await customerApi("status", { tracking }, c.signal);
        if (!c.signal.aborted) {
          setOrder(result);
          setError("");
        }
      } catch (e) {
        if (!c.signal.aborted) setError(e.message);
      }
    }
    const timer = setTimeout(load, 0),
      interval = setInterval(load, 5000);
    return () => {
      c.abort();
      clearTimeout(timer);
      clearInterval(interval);
    };
  }, [tracking, version]);
  const pending = order?.changes.some((c) => c.status === "requested");
  return (
    <main className="customer-tracker">
      <span className="menu-section-kicker">ACOMPANHE SEU PEDIDO</span>
      <h1>{order ? `Pedido #${order.number}` : "Consultando seu pedido…"}</h1>
      {error && (
        <p role="alert" className="customer-error">
          {error}
        </p>
      )}
      {notice && (
        <p role="status" className="customer-info">
          {notice}
        </p>
      )}
      {order && (
        <>
          <div className="customer-status">
            <Clock size={20} />
            <strong>{states[order.status] || order.status}</strong>
            <span>Atualização automática</span>
          </div>
          <div className="customer-track-grid">
            <section className="customer-panel">
              <h2>
                {order.fulfillment === "delivery"
                  ? "Seu pedido para entrega"
                  : "Seu pedido para retirada"}
              </h2>
              {order.items.map((i, n) => (
                <article key={n} className="customer-order-item">
                  <div>
                    <strong>
                      {i.quantity}× {i.name}
                    </strong>
                    <span>{money(i.unit_price_cents * i.quantity)}</span>
                  </div>
                  {i.modifiers.length > 0 && <p>{i.modifiers.join(" · ")}</p>}
                  {i.notes && <p>{i.notes}</p>}
                </article>
              ))}
              <div className="customer-summary">
                <span>
                  Produtos<strong>{money(order.subtotal_cents)}</strong>
                </span>
                <span>
                  Entrega<strong>{money(order.delivery_fee_cents)}</strong>
                </span>
                <span>
                  Total atual<strong>{money(order.total_cents)}</strong>
                </span>
              </div>
              <button
                type="button"
                className="customer-secondary"
                onClick={() =>
                  navigator.clipboard
                    ?.writeText(
                      `${location.origin}/pedido#acompanhar=${tracking}`,
                    )
                    .then(() =>
                      setNotice(
                        "Link privado copiado. Compartilhe apenas com quem pode acompanhar este pedido.",
                      ),
                    )
                    .catch(() =>
                      setNotice(
                        "Copie o endereço desta página. Ele é privado e permite acompanhar o pedido.",
                      ),
                    )
                }
              >
                Copiar link privado de acompanhamento
              </button>
            </section>
            <section className="customer-panel">
              <Payment key={order.revision} order={order} tracking={tracking} />
              {order.refund_due_cents > 0 && (
                <p className="customer-info" role="status">
                  Há {money(order.refund_due_cents)} a devolver após a
                  alteração. A administração precisa conferir e registrar a
                  devolução; ela não é executada automaticamente.
                </p>
              )}
              {shop?.whatsapp_number && (
                <a
                  className="customer-whatsapp"
                  href={`https://wa.me/${shop.whatsapp_number}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  Falar com a equipe
                </a>
              )}
            </section>
          </div>
          <section className="customer-panel customer-changes">
            <h2>Alterações no pedido</h2>
            {order.changes.map((c) => (
              <article key={c.id}>
                <strong>
                  {c.status === "requested"
                    ? "Em análise pela cozinha"
                    : c.status === "accepted"
                      ? "Alteração aceita"
                      : "Alteração não aceita"}
                </strong>
                <p>{c.reason}</p>
                {c.review_reason && (
                  <p>Retorno da cozinha: {c.review_reason}</p>
                )}
                {c.status === "requested" && (
                  <small>
                    {c.approved_sectors.length} de {c.sectors.length} setores
                    aprovaram.
                  </small>
                )}
              </article>
            ))}
            {change ? (
              <ChangeRequest
                key={order.revision}
                order={order}
                tracking={tracking}
                catalog={catalog}
                onDone={() => {
                  setChange(false);
                  setNotice(
                    "Solicitação enviada. Aguarde a análise da cozinha antes de considerar a alteração confirmada.",
                  );
                  setVersion((v) => v + 1);
                }}
              />
            ) : (
              <button
                type="button"
                className="customer-secondary"
                disabled={
                  pending || !["accepted", "preparing"].includes(order.status)
                }
                onClick={() => setChange(true)}
              >
                Solicitar alteração
              </button>
            )}
            {pending && (
              <p>
                A cozinha precisa concluir a solicitação atual antes de outra
                alteração.
              </p>
            )}
            <small>
              Alterações dependem da etapa de preparo e da aprovação da cozinha.
              Você acompanha o retorno aqui; avisos no WhatsApp dependem da sua
              autorização.
            </small>
          </section>
        </>
      )}
      <button type="button" className="customer-secondary" onClick={onNew}>
        Montar outro pedido
      </button>
    </main>
  );
}

export default function CustomerOrder() {
  const { items, setItems, clear } = useCart(),
    locationState = useLocation(),
    navigate = useNavigate();
  const hash = new URLSearchParams(locationState.hash.slice(1));
  const tracking = hash.get("acompanhar") || "";
  const [shop, setShop] = useState(null),
    [catalog, setCatalog] = useState([]),
    [configError, setConfigError] = useState("");
  const [fulfillment, setFulfillment] = useState(
      () => pendingRequest()?.fulfillment || "pickup",
    ),
    [method, setMethod] = useState(() => pendingRequest()?.method || "pix"),
    [needsChange, setNeedsChange] = useState(() =>
      Boolean(pendingRequest()?.change_for_cents),
    ),
    [changeFor, setChangeFor] = useState(() =>
      pendingRequest()?.change_for_cents
        ? (pendingRequest().change_for_cents / 100).toFixed(2)
        : "",
    );
  const [contact, setContact] = useState(
    () =>
      pendingRequest()?.contact || {
        name: "",
        phone: "",
        email: "",
        address: "",
        whatsapp_consent: false,
      },
  );
  const [quote, setQuote] = useState(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [submission, setSubmission] = useState(pendingRequest),
    [knownRejected, setKnownRejected] = useState(false);
  const suggestionApplied = useRef(false);
  useEffect(() => {
    document.title = "Planeta Lanches · Seu pedido";
  }, []);
  useEffect(() => {
    const c = new AbortController();
    const timer = setTimeout(
      () =>
        customerApi("config", {}, c.signal)
          .then((value) => {
            setShop(value);
            setCatalog(value.catalog || []);
            if (!pendingRequest() && !value.payments.pix && value.payments.card)
              setMethod("card");
            else if (
              !pendingRequest() &&
              !value.payments.pix &&
              value.cash_enabled
            )
              setMethod("cash");
          })
          .catch((e) => {
            if (!c.signal.aborted) setConfigError(e.message);
          }),
      0,
    );
    return () => {
      c.abort();
      clearTimeout(timer);
    };
  }, []);
  useEffect(() => {
    const suggestion = new URLSearchParams(locationState.hash.slice(1)).get(
      "sugestao",
    );
    if (
      !catalog.length ||
      !suggestion ||
      suggestionApplied.current ||
      pendingRequest()
    )
      return;
    const timer = setTimeout(() => {
      suggestionApplied.current = true;
      try {
        const proposed = JSON.parse(suggestion);
        if (!Array.isArray(proposed) || proposed.length > 30) return;
        const lines = proposed.map((i) => {
          const p = catalog.find((p) => p.product_id === i.product_id);
          if (
            !p ||
            !Number.isInteger(i.quantity) ||
            i.quantity < 1 ||
            i.quantity > 100 ||
            !Array.isArray(i.modifiers) ||
            i.modifiers.some((m) => !p.allowed_modifiers.includes(m))
          )
            throw new Error("invalid");
          return { ...draftLine(p, i.quantity), modifiers: i.modifiers };
        });
        setItems(lines);
        navigate("/pedido", { replace: true });
      } catch {
        setError(
          "Não foi possível aplicar a sugestão. Escolha os produtos no cardápio.",
        );
      }
    }, 0);
    return () => clearTimeout(timer);
  }, [catalog, locationState.hash, setItems, navigate]);
  const loadQuote = useCallback(
    (signal) =>
      customerApi("quote", { items: cartPayload(items), fulfillment }, signal),
    [items, fulfillment],
  );
  useEffect(() => {
    if (!items.length || !shop || tracking) return;
    const c = new AbortController();
    const timer = setTimeout(() => {
      setQuote(null);
      loadQuote(c.signal)
        .then(setQuote)
        .catch((e) => {
          if (!c.signal.aborted) setError(e.message);
        });
    }, 250);
    return () => {
      c.abort();
      clearTimeout(timer);
    };
  }, [items.length, shop, tracking, loadQuote]);
  function field(name, value) {
    setContact((p) => ({ ...p, [name]: value }));
  }
  async function submit(event) {
    event.preventDefault();
    if (busy || (!quote && !submission)) return;
    let request = submission;
    try {
      if (!request)
        request = {
          key: operationKey(),
          tracking: trackingToken(),
          items: cartPayload(items),
          contact: { ...contact, phone: phoneNumber(contact.phone) },
          fulfillment,
          method,
          change_for_cents:
            method === "cash" && needsChange ? cents(changeFor) : null,
          expected_total_cents: quote.total_cents,
          view_items: items,
        };
    } catch {
      setError("Informe um valor válido para o troco.");
      return;
    }
    try {
      sessionStorage.setItem(pendingSlot, JSON.stringify(request));
    } catch {
      setError(
        "Ative o armazenamento desta aba para preservar a tentativa antes de enviar.",
      );
      return;
    }
    setSubmission(request);
    setBusy(true);
    setKnownRejected(false);
    setError("");
    try {
      await customerApi("create", request);
      try {
        sessionStorage.setItem(
          "planeta:online:last-tracking",
          request.tracking,
        );
      } catch {
        /* O link continua no endereço da página. */
      }
      forgetPending();
      setSubmission(null);
      clear();
      navigate(`/pedido#acompanhar=${request.tracking}`, { replace: true });
    } catch (e) {
      setError(e.message);
      setKnownRejected(
        [
          "price_changed_review_order",
          "invalid_change_amount",
          "delivery_contact_required",
          "email_required",
          "invalid_contact",
          "product_unavailable",
          "invalid_modifier",
          "delivery_unavailable",
          "shop_closed",
        ].includes(e.code),
      );
    } finally {
      setBusy(false);
    }
  }
  const frozen = Boolean(submission);
  const shownItems = submission?.view_items || items;
  return (
    <div className="menu-page customer-order-page">
      <Header />
      {tracking && /^[a-f0-9]{64}$/.test(tracking) ? (
        <Tracker
          tracking={tracking}
          shop={shop}
          catalog={catalog}
          onNew={() => {
            setSubmission(null);
            navigate("/cardapio");
          }}
        />
      ) : (
        <main className="customer-checkout">
          <div className="customer-checkout-title">
            <span className="menu-section-kicker">DO SEU JEITO</span>
            <h1>Vamos fechar seu pedido?</h1>
            <p>
              Confira os itens, escolha como receber e veja o total antes de
              confirmar.
            </p>
          </div>
          {configError && (
            <p role="alert" className="customer-error">
              {configError}
            </p>
          )}
          {!shownItems.length ? (
            <section className="customer-panel customer-empty-cart">
              <ShoppingBag size={34} />
              <h2>Seu carrinho está esperando seu favorito.</h2>
              <Link to="/cardapio" className="customer-primary">
                Escolher produtos
                <ArrowRight size={18} />
              </Link>
              {/^[a-f0-9]{64}$/.test(lastTracking()) && (
                <Link to={`/pedido#acompanhar=${lastTracking()}`}>
                  Acompanhar meu último pedido
                </Link>
              )}
            </section>
          ) : (
            <form
              className="customer-checkout-grid"
              onSubmit={submit}
              noValidate={frozen}
            >
              <section className="customer-panel">
                <h2>1. Revise os itens</h2>
                <CartEditor
                  items={shownItems}
                  setItems={setItems}
                  catalog={catalog}
                  disabled={frozen}
                />
                {!frozen && (
                  <Link to="/cardapio">Adicionar mais produtos →</Link>
                )}
                {frozen && (
                  <p className="customer-info">
                    Há um envio pendente nesta aba. Retome a mesma tentativa
                    para recuperar o pedido sem duplicar a compra.
                  </p>
                )}
              </section>
              <section className="customer-panel customer-checkout-details">
                <h2>2. Como você quer receber?</h2>
                <fieldset disabled={frozen}>
                  <legend className="sr-only">Forma de recebimento</legend>
                  <label className="customer-option">
                    <input
                      type="radio"
                      checked={fulfillment === "pickup"}
                      onChange={() => setFulfillment("pickup")}
                      name="fulfillment"
                    />
                    <ShoppingBag size={19} />
                    <span>
                      Retirada na loja<small>Você busca seu pedido.</small>
                    </span>
                  </label>
                  <label className="customer-option">
                    <input
                      type="radio"
                      disabled={!shop?.delivery_enabled}
                      checked={fulfillment === "delivery"}
                      onChange={() => setFulfillment("delivery")}
                      name="fulfillment"
                    />
                    <Truck size={19} />
                    <span>
                      Entrega
                      <small>
                        {shop?.delivery_enabled
                          ? `Taxa: ${money(shop.delivery_fee_cents)}`
                          : "Entrega indisponível no momento."}
                      </small>
                    </span>
                  </label>
                  <label>
                    Seu nome
                    <input
                      autoComplete="name"
                      required
                      minLength={2}
                      maxLength={100}
                      value={contact.name}
                      onChange={(e) => field("name", e.target.value)}
                    />
                  </label>
                  <label>
                    WhatsApp com DDD
                    <input
                      type="tel"
                      autoComplete="tel"
                      required
                      maxLength={20}
                      placeholder="(81) 99999-9999"
                      value={contact.phone}
                      onChange={(e) => field("phone", e.target.value)}
                    />
                  </label>
                  <label>
                    E-mail para pagamentos e eventuais cobranças adicionais
                    <input
                      type="email"
                      autoComplete="email"
                      maxLength={254}
                      required
                      value={contact.email}
                      onChange={(e) => field("email", e.target.value)}
                    />
                  </label>
                  {fulfillment === "delivery" && (
                    <label>
                      Endereço completo para entrega
                      <textarea
                        required
                        minLength={10}
                        maxLength={500}
                        placeholder="Rua, número, bairro e referência."
                        value={contact.address}
                        onChange={(e) => field("address", e.target.value)}
                      />
                    </label>
                  )}
                </fieldset>
                <h2>3. Como prefere pagar?</h2>
                <fieldset disabled={frozen}>
                  <legend className="sr-only">Forma de pagamento</legend>
                  {[
                    ["pix", "Pix", shop?.payments.pix],
                    ["card", "Cartão online", shop?.payments.card],
                    ["cash", "Dinheiro", shop?.cash_enabled],
                  ].map(([id, label, available]) => (
                    <label className="customer-option" key={id}>
                      <input
                        type="radio"
                        name="payment-method"
                        disabled={!available}
                        checked={method === id}
                        onChange={() => setMethod(id)}
                      />
                      <span>
                        {label}
                        <small>
                          {!available
                            ? "Indisponível no momento"
                            : id === "card"
                              ? "Pagamento no ambiente seguro do provedor."
                              : id === "cash"
                                ? "O recebimento será conferido pela loja."
                                : shop.payments.manual_pix
                                  ? "Confirmação após conferência da loja."
                                  : "Confirmação pelo provedor."}
                        </small>
                      </span>
                    </label>
                  ))}
                  {method === "cash" && (
                    <>
                      <label className="customer-checkbox">
                        <input
                          type="checkbox"
                          checked={needsChange}
                          onChange={(e) => setNeedsChange(e.target.checked)}
                        />
                        Preciso de troco
                      </label>
                      {needsChange && (
                        <label>
                          Troco para quanto? (R$)
                          <input
                            required
                            inputMode="decimal"
                            placeholder="Ex.: 100,00"
                            value={changeFor}
                            onChange={(e) => setChangeFor(e.target.value)}
                          />
                        </label>
                      )}
                      <p className="customer-form-note">
                        Pedidos em dinheiro aguardam a confirmação da loja antes
                        de entrar na cozinha.
                      </p>
                    </>
                  )}
                </fieldset>
                <label className="customer-checkbox">
                  <input
                    type="checkbox"
                    disabled={frozen}
                    checked={contact.whatsapp_consent}
                    onChange={(e) =>
                      field("whatsapp_consent", e.target.checked)
                    }
                  />
                  Autorizo receber no WhatsApp os avisos deste pedido, inclusive
                  alterações aprovadas e cobranças pendentes.
                </label>
                <p className="customer-form-note">
                  Sem autorização, acompanhe as atualizações por seu link
                  privado no site. Dados de cartão são informados somente no
                  provedor de pagamento.
                </p>
                <div className="customer-summary">
                  <span>
                    Produtos
                    <strong>
                      {quote ? money(quote.subtotal_cents) : "Atualizando…"}
                    </strong>
                  </span>
                  <span>
                    Entrega
                    <strong>
                      {quote ? money(quote.delivery_fee_cents) : "—"}
                    </strong>
                  </span>
                  <span>
                    Total
                    <strong>
                      {submission
                        ? money(submission.expected_total_cents)
                        : quote
                          ? money(quote.total_cents)
                          : "—"}
                    </strong>
                  </span>
                </div>
                {error && (
                  <p role="alert" className="customer-error">
                    {error}
                  </p>
                )}
                {knownRejected && (
                  <button
                    type="button"
                    className="customer-secondary"
                    onClick={() => {
                      forgetPending();
                      setSubmission(null);
                      setKnownRejected(false);
                    }}
                  >
                    Corrigir dados do pedido
                  </button>
                )}
                <button
                  className="customer-primary customer-full"
                  disabled={
                    busy ||
                    !configured ||
                    !shop?.enabled ||
                    (!quote && !submission) ||
                    !shownItems.length
                  }
                >
                  {busy
                    ? "Confirmando…"
                    : submission
                      ? "Retomar mesmo envio"
                      : "Confirmar pedido"}
                  <ArrowRight size={18} />
                </button>
              </section>
            </form>
          )}
        </main>
      )}
      <CustomerChat shop={shop} catalog={catalog} />
    </div>
  );
}
