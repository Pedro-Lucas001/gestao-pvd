import { useState } from "react";
import { useAuth } from "../auth/context";
import { rpc } from "../lib/supabase";
import { money, cents } from "../lib/operations";
import { command } from "../admin/commands";
export default function CashDrawer({ shiftId }) {
  const { profile } = useAuth();
  const [open, setOpen] = useState(false),
    [data, setData] = useState(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  async function load() {
    setError("");
    try {
      setData(await rpc("cash_summary", { p_shift: shiftId }));
    } catch (e) {
      setError(e.message);
    }
  }
  return (
    <section className="cash-drawer">
      <button
        className="text-button"
        onClick={() => {
          setOpen(!open);
          if (!open) load();
        }}
      >
        Saldo do meu caixa · sangria e movimentos
      </button>
      {open && (
        <div className="management-panel">
          <h2>Caixa do seu turno</h2>
          {data && (
            <div className="metric-grid">
              <article className="metric">
                <span>Abertura</span>
                <strong>{money(data.opening_cents)}</strong>
              </article>
              <article className="metric">
                <span>Vendas em dinheiro</span>
                <strong>{money(data.cash_sales_cents)}</strong>
              </article>
              <article className="metric">
                <span>Movimentos</span>
                <strong>{money(data.movements_cents)}</strong>
              </article>
              <article className="metric">
                <span>Dinheiro esperado</span>
                <strong>{money(data.expected_cents)}</strong>
              </article>
            </div>
          )}
          <form
            className="form-columns"
            onSubmit={async (e) => {
              e.preventDefault();
              const form = e.currentTarget,
                f = new FormData(form);
              setBusy(true);
              setError("");
              try {
                await command("cash_movement", {
                  p_shift: shiftId,
                  p_kind: f.get("kind"),
                  p_amount: cents(String(f.get("amount"))),
                  p_reason: f.get("reason"),
                });
                form.reset();
                await load();
              } catch (e) {
                setError(e.message);
              } finally {
                setBusy(false);
              }
            }}
          >
            <label>
              Movimento
              <select name="kind">
                <option value="withdrawal">Sangria · retirada</option>
                {profile.role === "admin" && (
                  <option value="supply">Suprimento · entrada</option>
                )}
              </select>
            </label>
            <label>
              Valor físico movimentado (R$)
              <input name="amount" inputMode="decimal" required />
            </label>
            <label className="span-all">
              Justificativa
              <input name="reason" required minLength={5} maxLength={500} />
            </label>
            <button className="primary" disabled={busy}>
              Registrar movimento auditado
            </button>
          </form>
          <p>
            Somente valores do seu turno. O preço dos pedidos não é alterado por
            esta operação.
          </p>
        </div>
      )}
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
    </section>
  );
}
