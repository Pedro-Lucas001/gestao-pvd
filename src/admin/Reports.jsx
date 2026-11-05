import { useState, useEffect, useCallback } from "react";
import { rpc } from "../lib/supabase";
import DemandPanel from "../kds/DemandPanel";
import { money } from "../lib/operations";
export default function Reports() {
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Recife",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
  const [from, setFrom] = useState(today),
    [to, setTo] = useState(today),
    [data, setData] = useState(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  const load = useCallback(
    async (event) => {
      event?.preventDefault();
      setBusy(true);
      setError("");
      try {
        const end = new Date(`${to}T00:00:00-03:00`);
        end.setTime(end.getTime() + 86400000);
        setData(
          await rpc("admin_metrics", {
            p_from: new Date(`${from}T00:00:00-03:00`).toISOString(),
            p_to: end.toISOString(),
          }),
        );
      } catch (e) {
        setError(e.message);
      } finally {
        setBusy(false);
      }
    },
    [from, to],
  );
  useEffect(() => {
    const t = setTimeout(() => load(), 0);
    return () => clearTimeout(t);
  }, [load]);
  return (
    <section className="management">
      <span className="eyebrow">INTELIGÊNCIA DA OPERAÇÃO</span>
      <h1>Resultados do seu Planeta.</h1>
      <DemandPanel compact />
      <form className="filter-row" onSubmit={load}>
        <label>
          De
          <input
            type="date"
            required
            value={from}
            onChange={(e) => setFrom(e.target.value)}
          />
        </label>
        <label>
          Até
          <input
            type="date"
            required
            value={to}
            onChange={(e) => setTo(e.target.value)}
          />
        </label>
        <button className="primary" disabled={busy}>
          Atualizar período
        </button>
      </form>
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
      {data && (
        <>
          {Number(data.cancelled_credit_cents) > 0 && (
            <p className="error-message" role="alert">
              Há {money(data.cancelled_credit_cents)} recebidos em pedidos
              cancelados, ainda sem estorno confirmado. Confira Pagamentos e
              estornos.
            </p>
          )}
          <div className="metric-grid">
            {[
              ["Receita confirmada", money(data.revenue_cents)],
              ["Pedidos pagos", data.paid_orders],
              ["Descontos", money(data.discounts_cents)],
              ["Cancelados", data.cancelled],
            ].map(([label, value]) => (
              <article className="metric" key={label}>
                <span>{label}</span>
                <strong>{value}</strong>
              </article>
            ))}
          </div>
          <div className="management-grid">
            <article className="management-panel">
              <h2>Horários de pico · Carpina</h2>
              {!data.peaks.length && <p>Nenhuma venda paga neste período.</p>}
              {data.peaks.map((p) => (
                <div className="report-row" key={p.hour}>
                  <strong>{String(p.hour).padStart(2, "0")}h</strong>
                  <span>{p.orders} pedidos</span>
                  <b>{money(p.revenue_cents)}</b>
                </div>
              ))}
            </article>
            <article className="management-panel">
              <h2>Tempo por setor</h2>
              {data.bottlenecks.map((b) => (
                <div className="report-row" key={b.sector}>
                  <strong>{b.sector}</strong>
                  <span>Fila {Math.round(b.queue_seconds / 60)} min</span>
                  <span>Preparo {Math.round(b.prep_seconds / 60)} min</span>
                </div>
              ))}
              {!data.bottlenecks.length && (
                <p>Aguardando pedidos concluídos no KDS.</p>
              )}
            </article>
          </div>
          <article className="management-panel">
            <h2>Margem por ficha técnica</h2>
            <p>
              Custo atual da receita padrão; não é apuração contábil histórica.
              Modificadores de exclusão ainda não alteram a ficha.
            </p>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Produto</th>
                    <th>Preço</th>
                    <th>Custo estimado</th>
                    <th>Margem estimada</th>
                    <th>Vendidos</th>
                  </tr>
                </thead>
                <tbody>
                  {data.margins.map((p) => (
                    <tr key={p.id}>
                      <td>{p.name}</td>
                      <td>{money(p.price_cents)}</td>
                      <td>
                        {p.cost_cents === null
                          ? "Ficha não cadastrada"
                          : money(p.cost_cents)}
                      </td>
                      <td>
                        {p.margin_cents === null ? "—" : money(p.margin_cents)}
                      </td>
                      <td>{p.quantity}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </article>
          <article className="management-panel">
            <h2>Insumos abaixo do mínimo</h2>
            {data.low_stock.map((i) => (
              <div className="report-row" key={i.id}>
                <strong>{i.name}</strong>
                <span>
                  {i.stock} {i.unit}
                </span>
                <b>Mínimo {i.minimum_stock}</b>
              </div>
            ))}
            {!data.low_stock.length && (
              <p>Nenhum alerta entre os insumos cadastrados.</p>
            )}
          </article>
        </>
      )}
    </section>
  );
}
