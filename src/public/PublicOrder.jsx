import { useState, useEffect, useCallback } from "react";
import { QRCodeSVG } from "qrcode.react";
import { rpc, configured } from "../lib/supabase";
import { money, toggleModifier, normalize } from "../lib/operations";
import { invoke } from "../admin/commands";
const states = {
  pending_payment: "Aguardando pagamento",
  queued: "Na fila da cozinha",
  preparing: "Em preparo",
  ready: "Pronto",
  completed: "Concluído",
  cancelled: "Cancelado",
};
function fresh() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return {
    key: crypto.randomUUID(),
    tracking: Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join(
      "",
    ),
    paymentKey: crypto.randomUUID(),
    items: [],
    contact: {
      name: "",
      phone: "",
      address: "",
      email: "",
      whatsapp_consent: false,
    },
    order: null,
    submitted: false,
  };
}
export default function PublicOrder() {
  const token = new URLSearchParams(location.search).get("token") || "",
    slot = `planeta:checkout:${token.slice(0, 12)}`;
  const [draft, setDraft] = useState(() => {
      try {
        return JSON.parse(sessionStorage.getItem(slot)) || fresh();
      } catch {
        return fresh();
      }
    }),
    [menu, setMenu] = useState(null),
    [query, setQuery] = useState(""),
    [category, setCategory] = useState("all"),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [status, setStatus] = useState(null),
    [intent, setIntent] = useState(null);
  useEffect(() => {
    try {
      sessionStorage.setItem(slot, JSON.stringify(draft));
    } catch {
      /* Keep the current in-memory attempt. */
    }
  }, [draft, slot]);
  useEffect(() => {
    if (!configured) return;
    let active = true;
    rpc("checkout_menu", { p_token: token })
      .then((data) => {
        if (active) setMenu(data);
      })
      .catch(() => {
        if (active)
          setError(
            "Este link não está disponível ou expirou. Solicite um novo link à loja.",
          );
      });
    return () => {
      active = false;
    };
  }, [token]);
  const sync = useCallback(async () => {
    if (!draft.order) return;
    try {
      setStatus(await rpc("checkout_status", { p_tracking: draft.tracking }));
    } catch {
      setError(
        "Não foi possível atualizar o pedido. Ele permanece registrado; tente novamente.",
      );
    }
  }, [draft.order, draft.tracking]);
  useEffect(() => {
    if (!draft.order) return;
    const t = setTimeout(sync, 0),
      timer = setInterval(sync, 10000);
    return () => {
      clearTimeout(t);
      clearInterval(timer);
    };
  }, [draft.order, sync]);
  const frozen = Boolean(draft.order) || draft.submitted || busy;
  function add(p) {
    if (frozen) return;
    const existing = draft.items.find(
      (i) => i.id === p.id && !i.modifiers.length && !i.notes,
    );
    if (!existing && draft.items.length >= 30) {
      setError("Limite de 30 linhas no pedido.");
      return;
    }
    setDraft({
      ...draft,
      items: existing
        ? draft.items.map((i) =>
            i.lineId === existing.lineId
              ? { ...i, quantity: Math.min(100, i.quantity + 1) }
              : i,
          )
        : [
            ...draft.items,
            {
              ...p,
              lineId: crypto.randomUUID(),
              quantity: 1,
              modifiers: [],
              notes: "",
            },
          ],
    });
  }
  function update(id, change) {
    if (frozen) return;
    setDraft({
      ...draft,
      items: draft.items
        .map((i) => (i.lineId === id ? { ...i, ...change } : i))
        .filter((i) => i.quantity > 0),
    });
  }
  async function submit(e) {
    e.preventDefault();
    if (!navigator.onLine) {
      setError(
        "Sem internet. Seu pedido ainda não foi confirmado. Reconecte e retome a mesma tentativa.",
      );
      return;
    }
    setBusy(true);
    setError("");
    setDraft((prev) => ({ ...prev, submitted: true }));
    try {
      const order = await rpc("checkout_order", {
        p_token: token,
        p_key: draft.key,
        p_tracking: draft.tracking,
        p_contact: draft.contact,
        p_items: draft.items.map((i) => ({
          product_id: i.id,
          quantity: i.quantity,
          modifiers: i.modifiers,
          notes: i.notes,
        })),
      });
      setDraft((prev) => ({
        ...prev,
        order,
        submitted: false,
        contact: fresh().contact,
        items: [],
      }));
    } catch (e) {
      setError(e.message);
      if (e.rejected) setDraft((prev) => ({ ...prev, submitted: false }));
    } finally {
      setBusy(false);
    }
  }
  async function pay() {
    setBusy(true);
    setError("");
    try {
      setIntent(
        await invoke("checkout-payment", {
          tracking: draft.tracking,
          key: draft.paymentKey,
        }),
      );
      await sync();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  const current = status || draft.order;
  const pix = intent?.pix || status?.pix;
  if (!configured)
    return (
      <main className="public-checkout">
        <h1>Planeta Lanches</h1>
        <p>
          O autoatendimento ainda não foi configurado pela loja. Fale com a
          equipe para fazer seu pedido.
        </p>
      </main>
    );
  return (
    <main className="public-checkout">
      <header>
        <img src="/brand/favicon.svg" alt="" />
        <div>
          <h1>Planeta Lanches</h1>
          <p>{menu?.label || "Seu pedido, do seu jeito."}</p>
        </div>
      </header>
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
      {current ? (
        <section className="management-panel">
          <span className="eyebrow">PEDIDO #{current.number}</span>
          <h2>{states[current.status] || current.status}</h2>
          <strong className="public-total">{money(current.total_cents)}</strong>
          <p>
            {current.fulfillment_state === "dispatched"
              ? "Seu pedido saiu para entrega."
              : current.status === "pending_payment"
                ? "O pedido só entra na cozinha após a confirmação do recebimento. Você também pode informar o número à equipe e pagar no caixa."
                : "Acompanhe as atualizações nesta página."}
          </p>
          {current.status === "pending_payment" && (
            <>
              <p>
                Pix Nubank: o administrador confere o crédito no extrato. Gerar
                ou copiar o QR não confirma o pagamento.
              </p>
              <button className="primary" disabled={busy} onClick={pay}>
                {pix ? "Retomar Pix do pedido" : "Gerar Pix com valor exato"}
              </button>
              {pix && (
                <div className="pix-code">
                  <QRCodeSVG value={pix.copyPaste} size={200} />
                  <p>
                    QR estático com o valor do pedido, sem expiração bancária
                    automática.
                  </p>
                  <button
                    className="secondary"
                    onClick={() => navigator.clipboard.writeText(pix.copyPaste)}
                  >
                    Copiar código Pix
                  </button>
                  <code>{pix.copyPaste}</code>
                </div>
              )}
            </>
          )}
          <button className="text-button" onClick={sync}>
            Atualizar status
          </button>
          {["completed", "cancelled"].includes(current.status) && (
            <button
              className="secondary"
              onClick={() => {
                setDraft(fresh());
                setStatus(null);
                setIntent(null);
              }}
            >
              Começar outro pedido
            </button>
          )}
          <p>
            Guarde esta página neste dispositivo para acompanhar. O código de
            acompanhamento é pessoal.
          </p>
        </section>
      ) : menu ? (
        <>
          <label className="search-box">
            <input
              aria-label="Buscar no cardápio"
              placeholder="Buscar um sabor…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </label>
          <div className="category-tabs">
            <button
              className={category === "all" ? "active" : ""}
              onClick={() => setCategory("all")}
            >
              Todos
            </button>
            {[...new Set(menu.products.map((p) => p.category))].map((c) => (
              <button
                key={c}
                className={category === c ? "active" : ""}
                onClick={() => setCategory(c)}
              >
                {c}
              </button>
            ))}
          </div>
          <div className="public-product-grid">
            {menu.products
              .filter(
                (p) =>
                  (category === "all" || p.category === category) &&
                  normalize(p.name + " " + p.description).includes(
                    normalize(query),
                  ),
              )
              .map((p) => (
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
                  </div>
                  <div className="product-info">
                    <h3>{p.name}</h3>
                    <p>{p.description}</p>
                    <div>
                      <strong>{money(p.price_cents)}</strong>
                      <span>＋</span>
                    </div>
                  </div>
                </button>
              ))}
          </div>
          <form className="management-panel public-cart" onSubmit={submit}>
            <h2>Seu pedido</h2>
            {draft.items.map((i) => (
              <article className="cart-line" key={i.lineId}>
                <div className="report-row">
                  <strong>
                    {i.quantity}× {i.name}
                  </strong>
                  <b>{money(i.price_cents * i.quantity)}</b>
                  <button
                    className="icon-button"
                    type="button"
                    disabled={frozen}
                    aria-label={`Diminuir ${i.name}`}
                    onClick={() =>
                      update(i.lineId, { quantity: i.quantity - 1 })
                    }
                  >
                    −
                  </button>
                  <button
                    className="icon-button"
                    type="button"
                    disabled={frozen}
                    aria-label={`Aumentar ${i.name}`}
                    onClick={() =>
                      update(i.lineId, {
                        quantity: Math.min(100, i.quantity + 1),
                      })
                    }
                  >
                    ＋
                  </button>
                </div>
                <div className="modifier-options">
                  {i.allowed_modifiers.map((m) => (
                    <button
                      type="button"
                      key={m}
                      disabled={frozen}
                      className={i.modifiers.includes(m) ? "active" : ""}
                      onClick={() =>
                        update(i.lineId, {
                          modifiers: toggleModifier(i.modifiers, m),
                        })
                      }
                    >
                      {m}
                    </button>
                  ))}
                </div>
                <label>
                  Detalhes para a cozinha · sem dados pessoais
                  <textarea
                    disabled={frozen}
                    maxLength={500}
                    value={i.notes}
                    onChange={(e) =>
                      update(i.lineId, { notes: e.target.value })
                    }
                  />
                </label>
              </article>
            ))}
            <div className="subtotal">
              <span>Total · confirmado pelo sistema ao enviar</span>
              <strong>
                {money(
                  draft.items.reduce(
                    (s, i) => s + i.quantity * i.price_cents,
                    0,
                  ),
                )}
              </strong>
            </div>
            <label>
              Nome
              <input
                required
                minLength={2}
                maxLength={100}
                value={draft.contact.name}
                disabled={frozen}
                onChange={(e) =>
                  setDraft({
                    ...draft,
                    contact: { ...draft.contact, name: e.target.value },
                  })
                }
              />
            </label>
            <label>
              Telefone com DDD
              <input
                type="tel"
                required={
                  menu.channel === "delivery" || draft.contact.whatsapp_consent
                }
                pattern="\+?[0-9]{10,15}"
                maxLength={16}
                placeholder="5581999999999"
                value={draft.contact.phone}
                disabled={frozen}
                onChange={(e) =>
                  setDraft({
                    ...draft,
                    contact: { ...draft.contact, phone: e.target.value },
                  })
                }
              />
            </label>
            {menu.channel === "delivery" && (
              <label>
                Endereço completo para entrega
                <textarea
                  required
                  minLength={10}
                  maxLength={500}
                  value={draft.contact.address}
                  disabled={frozen}
                  onChange={(e) =>
                    setDraft({
                      ...draft,
                      contact: { ...draft.contact, address: e.target.value },
                    })
                  }
                />
              </label>
            )}
            <label className="check-label">
              <input
                type="checkbox"
                disabled={frozen}
                checked={draft.contact.whatsapp_consent}
                onChange={(e) =>
                  setDraft({
                    ...draft,
                    contact: {
                      ...draft.contact,
                      whatsapp_consent: e.target.checked,
                    },
                  })
                }
              />
              Quero receber atualizações deste pedido pelo WhatsApp, quando o
              serviço estiver habilitado.
            </label>
            <p>
              Usamos seus dados para atender e entregar este pedido. Telefone e
              endereço não são enviados à cozinha. Solicitações de acesso ou
              exclusão podem ser feitas à administração da loja. Não há
              autorização de marketing neste formulário.
            </p>
            <button
              className="primary full"
              disabled={!draft.items.length || busy}
            >
              {busy
                ? "Enviando…"
                : draft.submitted
                  ? "Reenviar mesma tentativa"
                  : "Enviar pedido e seguir para pagamento"}
            </button>
          </form>
        </>
      ) : (
        !error && <div className="loading">Carregando cardápio…</div>
      )}
    </main>
  );
}
