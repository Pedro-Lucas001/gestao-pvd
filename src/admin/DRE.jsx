import { useCallback, useEffect, useState } from "react";
import { rpc } from "../lib/supabase";
import { cents, money } from "../lib/operations";
import { command } from "./commands";
export default function DRE() {
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Recife",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
  const [from, setFrom] = useState(today.slice(0, 8) + "01"),
    [to, setTo] = useState(today),
    [data, setData] = useState(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    const end = new Date(`${to}T00:00:00-03:00`);
    end.setTime(end.getTime() + 86400000);
    try {
      setData(
        await rpc("admin_dre", {
          p_from: new Date(`${from}T00:00:00-03:00`).toISOString(),
          p_to: end.toISOString(),
        }),
      );
    } catch (error) {
      setError(error.message);
    }
  }, [from, to]);
  useEffect(() => {
    const timer = setTimeout(load, 0);
    return () => clearTimeout(timer);
  }, [load]);
  return (
    <section className="management">
      <span className="eyebrow">ADMINISTRAÇÃO · FINANCEIRO</span>
      <h1>DRE gerencial.</h1>
      <p>
        Recebimentos, insumos e despesas lançadas. Os estornos acompanham as
        vendas do período, no estado atual.
      </p>
      <form
        className="filter-row"
        onSubmit={(event) => {
          event.preventDefault();
          setError("");
          load();
        }}
      >
        <label>
          De<input
            type="date"
            value={from}
            required
            onChange={(e) => setFrom(e.target.value)}
          />
        </label>
        <label>
          Até<input
            type="date"
            value={to}
            required
            onChange={(e) => setTo(e.target.value)}
          />
        </label>
        <button className="primary">Atualizar período</button>
      </form>
      {error && <p className="error-message" role="alert">{error}</p>}
      {data && (
        <>
          <article className="management-panel dre-statement">
            {[
              ["Vendas recebidas · após descontos", data.sales_cents],
              ["(−) Estornos confirmados", -data.refunds_cents],
              ["Receita líquida", data.net_revenue_cents],
              ["(−) Insumos consumidos", -data.cost_cents],
              ["(−) Despesas operacionais lançadas", -data.expense_cents],
            ].map(([label, amount]) => (
              <div className="report-row" key={label}>
                <strong>{label}</strong>
                <b>{money(amount)}</b>
              </div>
            ))}
            <div className="report-row dre-result">
              <strong>
                Resultado gerencial {data.legacy_cost_entries ? "estimado" : ""}
              </strong>
              <b>
                {data.result_cents === null
                  ? "Custos incompletos"
                  : money(data.result_cents)}
              </b>
            </div>
            <p>
              Descontos já incluídos nas vendas:{" "}
              {money(data.discounts_cents)}. Sangrias e suprimentos não são
              despesas. Tributos e despesas não cadastrados não são deduzidos
              automaticamente.
            </p>
            {data.products_without_recipe > 0 && (
              <p className="error-message">
                Há {data.products_without_recipe}{" "}
                produtos vendidos sem ficha técnica. Cadastre os custos para
                apurar o resultado.
              </p>
            )}
            {data.legacy_cost_entries > 0 && (
              <p className="offline-banner">
                {data.legacy_cost_entries}{" "}
                movimentos antigos usam o custo atual do insumo. Novas baixas
                guardam o custo do momento da venda.
              </p>
            )}
          </article>
          <article className="management-panel">
            <h2>Despesas do período</h2>
            {!data.expenses.length && <p>Nenhuma despesa registrada.</p>}
            {data.expenses.map((e) => (
              <div className="report-row" key={e.id}>
                <strong>{e.description}</strong>
                <span>{e.expense_date}</span>
                <b>{money(e.amount_cents)}</b>
              </div>
            ))}
          </article>
        </>
      )}
      <form
        className="management-panel form-columns"
        onSubmit={async (event) => {
          event.preventDefault();
          const form = event.currentTarget, fields = new FormData(form);
          setBusy(true);
          setError("");
          try {
            await command("record_operating_expense", {
              p_description: fields.get("description").trim(),
              p_amount: cents(fields.get("amount")),
              p_date: fields.get("date"),
              p_reason: fields.get("reason").trim(),
            });
            form.reset();
            await load();
          } catch (error) {
            setError(error.message);
          } finally {
            setBusy(false);
          }
        }}
      >
        <h2 className="span-all">Registrar despesa operacional</h2>
        <label>
          Descrição<input
            name="description"
            required
            minLength={2}
            maxLength={150}
          />
        </label>
        <label>
          Valor · R$<input
            name="amount"
            required
            inputMode="decimal"
            placeholder="0,00"
          />
        </label>
        <label>
          Data<input name="date" type="date" required defaultValue={today} />
        </label>
        <label>
          Justificativa<input
            name="reason"
            required
            minLength={5}
            maxLength={500}
          />
        </label>
        <button className="primary" disabled={busy}>
          {busy ? "Registrando…" : "Registrar despesa"}
        </button>
      </form>
    </section>
  );
}
