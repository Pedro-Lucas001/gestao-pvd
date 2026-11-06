import { useEffect, useState, useCallback } from "react";
import { useAuth } from "../auth/context";
import { supabase, rpc } from "../lib/supabase";
import { money } from "../lib/operations";
import { invoke } from "./commands";
export default function Fulfillment() {
  const { profile } = useAuth();
  const admin = profile.role === "admin";
  const [queue, setQueue] = useState([]),
    [contacts, setContacts] = useState([]),
    [inbox, setInbox] = useState([]),
    [operators, setOperators] = useState([]),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    const [q, c, i] = await Promise.all([
      rpc("external_order_queue"),
      supabase
        .from("customer_contacts")
        .select(
          "order_id,name,phone,address,assigned_to,orders!inner(id,number,status,fulfillment_state,total_cents)",
        )
        .is("erased_at", null)
        .in("orders.status", ["queued", "preparing", "ready"])
        .order("created_at", { ascending: false })
        .limit(50),
      supabase
        .from("whatsapp_inbox")
        .select("id,sender,body,received_at,assigned_to")
        .is("closed_at", null)
        .order("received_at", { ascending: false })
        .limit(50),
    ]);
    if (c.error || i.error)
      throw new Error("Não foi possível consultar os atendimentos.");
    setQueue(q);
    setContacts(c.data);
    setInbox(i.data);
    if (admin) {
      const { data } = await supabase
        .from("profiles")
        .select("id,name,role")
        .eq("active", true)
        .in("role", ["admin", "cashier"]);
      setOperators(data || []);
    }
  }, [admin]);
  const run = useCallback(
    async (fn) => {
      setBusy(true);
      setError("");
      try {
        await fn();
        await load();
      } catch (e) {
        setError(e.message);
      } finally {
        setBusy(false);
      }
    },
    [load],
  );
  useEffect(() => {
    const t = setTimeout(() => run(async () => {}), 0);
    return () => clearTimeout(t);
  }, [run]);
  return (
    <section className="management">
      <span className="eyebrow">ATENDIMENTO E DELIVERY</span>
      <h1>Da chegada à entrega.</h1>
      <p>
        Telefone e endereço aparecem apenas ao administrador e ao operador
        responsável enquanto o pedido está em andamento. A cozinha recebe
        somente itens e número do pedido.
      </p>
      <button
        className="secondary"
        onClick={() => run(async () => {})}
        disabled={busy}
      >
        Sincronizar atendimentos
      </button>
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
      <article className="management-panel">
        <h2>Pedidos automáticos sem responsável</h2>
        {queue.map((o) => (
          <div className="report-row" key={o.id}>
            <strong>
              #{o.number} · {o.channel}
            </strong>
            <span>{money(o.total_cents)}</span>
            <button
              className="text-button"
              disabled={busy}
              onClick={() =>
                run(() => rpc("claim_external_order", { p_order: o.id }))
              }
            >
              Assumir no meu caixa
            </button>
          </div>
        ))}
        {!queue.length && (
          <p>
            Nenhum pedido aguardando atribuição. Para assumir um pedido,
            mantenha seu caixa aberto.
          </p>
        )}
      </article>
      <div className="management-grid">
        {contacts.map((c) => (
          <article className="management-panel" key={c.order_id}>
            <h2>
              #{c.orders.number} · {c.name}
            </h2>
            <p>
              {c.orders.status} · {c.orders.fulfillment_state}
            </p>
            <dl>
              <dt>Telefone</dt>
              <dd>{c.phone || "Não informado"}</dd>
              <dt>Endereço</dt>
              <dd>{c.address || "Atendimento na mesa"}</dd>
            </dl>
            {c.orders.status === "ready" && (
              <div className="button-row">
                <button
                  className="secondary"
                  disabled={busy || c.orders.fulfillment_state === "dispatched"}
                  onClick={() =>
                    run(() => rpc("dispatch_order", { p_order: c.order_id }))
                  }
                >
                  Saiu para entrega
                </button>
                <button
                  className="primary"
                  disabled={busy}
                  onClick={() => {
                    if (confirm("Confirmar a entrega/retirada deste pedido?"))
                      run(() => rpc("deliver_order", { p_order: c.order_id }));
                  }}
                >
                  Confirmar entrega
                </button>
              </div>
            )}
          </article>
        ))}
      </div>
      <article className="management-panel">
        <h2>Caixa de entrada · API oficial do WhatsApp</h2>
        <p>
          O aplicativo WhatsApp Business sozinho não fornece os webhooks. As
          conversas aparecerão após habilitar e configurar a API oficial.
        </p>
        {inbox.map((m) => (
          <div className="conversation" key={m.id}>
            <strong>{m.sender}</strong>
            <small>{new Date(m.received_at).toLocaleString("pt-BR")}</small>
            <p>{m.body}</p>
            {profile.role === "admin" && (
              <select
                aria-label={`Responsável pela conversa ${m.id}`}
                value={m.assigned_to || ""}
                onChange={(e) => {
                  if (e.target.value)
                    run(() =>
                      rpc("assign_whatsapp", {
                        p_id: m.id,
                        p_user: e.target.value,
                      }),
                    );
                }}
              >
                <option value="">Atribuir atendimento</option>
                {operators.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.name}
                  </option>
                ))}
              </select>
            )}
            <form
              onSubmit={(e) => {
                e.preventDefault();
                const text = new FormData(e.currentTarget).get("reply");
                run(() => invoke("whatsapp-send", { inboxId: m.id, text }));
              }}
            >
              <label>
                Resposta
                <textarea name="reply" required maxLength={2000} />
              </label>
              <button className="primary" disabled={busy}>
                Enviar pela API oficial
              </button>
            </form>
            <button
              className="text-button"
              disabled={busy}
              onClick={() => {
                const reason = prompt(
                  "Justificativa para encerrar a conversa:",
                );
                if (reason)
                  run(() =>
                    rpc("close_conversation", { p_id: m.id, p_reason: reason }),
                  );
              }}
            >
              Encerrar atendimento
            </button>
          </div>
        ))}
      </article>
    </section>
  );
}
