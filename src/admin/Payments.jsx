import { useState, useEffect } from "react";
import { supabase, rpc } from "../lib/supabase";
import { money, cents } from "../lib/operations";
import { command } from "./commands";
export default function Payments() {
  const [payments, setPayments] = useState([]),
    [refunds, setRefunds] = useState([]),
    [orders, setOrders] = useState([]),
    [shift, setShift] = useState(null),
    [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false);
  async function load() {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    const [p, r, o, s] = await Promise.all([
      supabase
        .from("payment_attempts")
        .select(
          "id,order_id,method,status,amount_cents,provider_reference,confirmation_mode,created_at",
        )
        .order("created_at", { ascending: false })
        .limit(100),
      supabase
        .from("refunds")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(100),
      supabase
        .from("orders")
        .select(
          "id,number,customer,status,total_cents,subtotal_cents,discount_cents",
        )
        .order("created_at", { ascending: false })
        .limit(100),
      supabase
        .from("shifts")
        .select("id")
        .eq("cashier_id", user.id)
        .is("closed_at", null)
        .maybeSingle(),
    ]);
    if (p.error || r.error || o.error || s.error)
      setError("Não foi possível sincronizar os pagamentos.");
    else {
      setPayments(p.data);
      setRefunds(r.data);
      setOrders(o.data);
      setShift(s.data);
    }
  }
  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, []);
  async function run(fn) {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await fn();
      setNotice("Operação registrada.");
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  const orderName = (id) => {
    const order = orders.find((o) => o.id === id);
    return order ? `#${order.number} · ${order.customer}` : id;
  };
  return (
    <section className="management">
      <span className="eyebrow">FINANCEIRO · ADMINISTRADOR</span>
      <h1>Recebimentos e estornos.</h1>
      <p>
        Pix Nubank de conta física exige conferência no extrato. Este painel não
        acessa o aplicativo bancário e não transfere dinheiro automaticamente.
      </p>
      <button className="secondary" onClick={load}>
        Sincronizar
      </button>
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
      {notice && (
        <p className="success-message" role="status">
          {notice}
        </p>
      )}
      <article className="management-panel">
        <h2>Pix pendente ou encerrado para conciliação</h2>
        {payments
          .filter(
            (p) =>
              p.method === "pix" &&
              (p.status === "pending" ||
                (p.status === "failed" &&
                  p.confirmation_mode === "manual_pix")),
          )
          .map((p) => (
            <form
              className="sensitive-operation"
              key={p.id}
              onSubmit={(e) => {
                e.preventDefault();
                const f = new FormData(e.currentTarget);
                run(() =>
                  rpc("confirm_manual_pix", {
                    p_attempt: p.id,
                    p_bank_reference: f.get("reference"),
                    p_reason: f.get("reason"),
                  }),
                );
              }}
            >
              <div>
                <strong>{orderName(p.order_id)}</strong>
                <b>{money(p.amount_cents)}</b>
              </div>
              <label>
                Referência da transação no extrato Nubank
                <input
                  name="reference"
                  required
                  minLength={8}
                  maxLength={100}
                  autoComplete="off"
                />
              </label>
              <label>
                Justificativa da confirmação
                <input name="reason" required minLength={5} maxLength={500} />
              </label>
              <label className="check-label">
                <input type="checkbox" required />
                Conferi o crédito efetivo do valor exato no extrato, não apenas
                um comprovante enviado.
              </label>
              <button className="primary" disabled={busy}>
                {orders.find((o) => o.id === p.order_id)?.status === "cancelled"
                  ? "Registrar crédito tardio · sem liberar cozinha"
                  : "Registrar recebimento e liberar cozinha"}
              </button>
              {p.status === "pending" &&
                p.confirmation_mode === "manual_pix" && (
                  <button
                    type="button"
                    className="secondary"
                    disabled={busy}
                    onClick={() => {
                      if (
                        !confirm(
                          "Encerrar sem crédito? O QR estático pode continuar pagável no banco. Créditos tardios exigem nova conferência e devolução.",
                        )
                      )
                        return;
                      const reason = prompt(
                        "Justificativa após conferir que não houve crédito:",
                      );
                      if (reason)
                        run(() =>
                          rpc("void_pending_manual_pix", {
                            p_order: p.order_id,
                            p_reason: reason,
                          }),
                        );
                    }}
                  >
                    Encerrar Pix sem crédito confirmado
                  </button>
                )}
            </form>
          ))}
        {!payments.some(
          (p) =>
            p.method === "pix" &&
            (p.status === "pending" ||
              (p.status === "failed" && p.confirmation_mode === "manual_pix")),
        ) && <p>Nenhum Pix pendente entre os últimos 100 registros.</p>}
      </article>
      <div className="management-grid">
        <form
          className="management-panel"
          onSubmit={(e) => {
            e.preventDefault();
            const f = new FormData(e.currentTarget);
            run(() =>
              rpc("apply_discount", {
                p_order: f.get("order"),
                p_discount: cents(String(f.get("amount"))),
                p_reason: f.get("reason"),
              }),
            );
          }}
        >
          <h2>Desconto autorizado</h2>
          <p>
            Somente antes de iniciar uma cobrança. O preço original e a
            justificativa ficam registrados.
          </p>
          <label>
            Pedido
            <select name="order" required>
              <option value="">Selecione</option>
              {orders
                .filter((o) => o.status === "pending_payment")
                .map((o) => (
                  <option key={o.id} value={o.id}>
                    #{o.number} · {money(o.total_cents)}
                  </option>
                ))}
            </select>
          </label>
          <label>
            Desconto total em R$
            <input name="amount" required inputMode="decimal" />
          </label>
          <label>
            Justificativa
            <input name="reason" required minLength={5} maxLength={500} />
          </label>
          <button className="primary" disabled={busy}>
            Aplicar desconto
          </button>
        </form>
        <form
          className="management-panel"
          onSubmit={(e) => {
            e.preventDefault();
            const f = new FormData(e.currentTarget);
            run(() =>
              command("request_refund", {
                p_order: f.get("order"),
                p_reason: f.get("reason"),
              }),
            );
          }}
        >
          <h2>Solicitar estorno integral</h2>
          <p>
            A solicitação não devolve o dinheiro. Conclua o procedimento
            correspondente abaixo. Não repõe insumos já utilizados.
          </p>
          <label>
            Venda
            <select name="order" required>
              <option value="">Selecione</option>
              {payments
                .filter((p) => p.status === "confirmed")
                .map((p) => (
                  <option key={p.id} value={p.order_id}>
                    {orderName(p.order_id)} · {money(p.amount_cents)} ·{" "}
                    {p.method}
                  </option>
                ))}
            </select>
          </label>
          <label>
            Justificativa
            <input name="reason" required minLength={5} maxLength={500} />
          </label>
          <button className="primary" disabled={busy}>
            Abrir solicitação de estorno
          </button>
        </form>
      </div>
      <article className="management-panel">
        <h2>Solicitações de estorno</h2>
        {refunds.map((r) => {
          const p = payments.find((p) => p.id === r.payment_id);
          return (
            <div className="sensitive-operation" key={r.id}>
              <div>
                <strong>{orderName(r.order_id)}</strong>
                <b>
                  {money(r.amount_cents)} · {r.state}
                </b>
              </div>
              <p>{r.reason}</p>
              {r.state === "pending" &&
                (p?.method === "cash" ? (
                  <>
                    <p>
                      Retirada física do caixa aberto do administrador. É
                      registrada como saída de caixa.
                    </p>
                    <button
                      className="primary"
                      disabled={!shift || busy}
                      onClick={() => {
                        if (
                          confirm(
                            "Confirma a devolução física ao cliente a partir do seu caixa?",
                          )
                        )
                          run(() =>
                            rpc("refund_cash", {
                              p_refund: r.id,
                              p_shift: shift.id,
                            }),
                          );
                      }}
                    >
                      {shift
                        ? "Confirmar devolução em dinheiro"
                        : "Abra o seu caixa para devolver dinheiro"}
                    </button>
                  </>
                ) : p?.provider_reference?.startsWith("manual-pix:") ? (
                  <form
                    onSubmit={(e) => {
                      e.preventDefault();
                      const f = new FormData(e.currentTarget);
                      run(() =>
                        rpc("confirm_manual_pix_refund", {
                          p_refund: r.id,
                          p_bank_reference: f.get("reference"),
                        }),
                      );
                    }}
                  >
                    <label>
                      Referência da devolução já feita no aplicativo Nubank
                      <input
                        name="reference"
                        required
                        minLength={8}
                        maxLength={100}
                      />
                    </label>
                    <label className="check-label">
                      <input type="checkbox" required />A devolução integral já
                      foi concluída no banco.
                    </label>
                    <button className="primary" disabled={busy}>
                      Registrar devolução Pix concluída
                    </button>
                  </form>
                ) : (
                  <p>
                    Esta venda exige o adaptador homologado do provedor que a
                    processou. A devolução automática não está configurada.
                  </p>
                ))}
            </div>
          );
        })}
        {!refunds.length && <p>Nenhuma solicitação registrada.</p>}
      </article>
    </section>
  );
}
