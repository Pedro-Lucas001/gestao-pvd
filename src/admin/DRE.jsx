import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { rpc, supabase } from "../lib/supabase";
import { command } from "./commands";
import { cents, money } from "../lib/operations";
function today() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Recife",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}
export default function DRE() {
  const [reference, setReference] = useState(today),
    [summary, setSummary] = useState(null),
    [expenses, setExpenses] = useState([]),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [version, setVersion] = useState(0),
    [success, setSuccess] = useState("");
  useEffect(() => {
    let alive = true;
    async function load() {
      try {
        const snapshot = await rpc("admin_control_snapshot", {
            p_reference: reference,
          }),
          p = snapshot.periods.month;
        const { data, error } = await supabase
          .from("operating_expenses")
          .select("id,description,amount_cents,expense_date")
          .gte("expense_date", p.from)
          .lte("expense_date", p.to)
          .order("expense_date", { ascending: false });
        if (error) throw error;
        if (alive) {
          setSummary(p);
          setExpenses(data);
          setError("");
        }
      } catch {
        if (alive) {
          setError("Não foi possível consultar o resultado e as despesas.");
          setSummary(null);
        }
      }
    }
    const t = setTimeout(load, 0);
    return () => {
      alive = false;
      clearTimeout(t);
    };
  }, [reference, version]);
  async function submit(e) {
    e.preventDefault();
    const form = e.currentTarget,
      f = new FormData(form);
    setBusy(true);
    setError("");
    setSuccess("");
    try {
      await command("record_operating_expense", {
        p_description: f.get("description"),
        p_amount: cents(String(f.get("amount"))),
        p_date: f.get("date"),
        p_reason: f.get("reason"),
      });
      form.reset();
      setSuccess("Despesa registrada. O resultado considera a data informada.");
      setVersion((v) => v + 1);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="management">
      <span className="eyebrow">RESULTADO GERENCIAL</span>
      <h1>Recebimentos, custos e despesas.</h1>
      <p>
        Resultado por movimentos confirmados do balcão e do site. Registre as
        despesas reais da operação para acompanhar a estimativa no dashboard.
      </p>
      <label>
        Data de referência do mês
        <input
          type="date"
          required
          value={reference}
          max={today()}
          onChange={(e) => e.target.value && setReference(e.target.value)}
        />
      </label>
      {error && (
        <p role="alert" className="error-message">
          {error}
        </p>
      )}
      {success && (
        <p role="status" className="control-success">
          {success}
        </p>
      )}
      {summary && (
        <div className="metric-grid">
          {[
            ["Recebimentos após devoluções", money(summary.net_received_cents)],
            ["Custo dos insumos baixados", money(summary.cost_cents)],
            ["Despesas registradas", money(summary.expenses_cents)],
            [
              "Resultado estimado",
              summary.result_cents === null
                ? "Custos incompletos"
                : money(summary.result_cents),
            ],
          ].map(([label, value]) => (
            <article className="metric" key={label}>
              <span>{label}</span>
              <strong>{value}</strong>
            </article>
          ))}
        </div>
      )}
      <p>
        O resultado depende de fichas, custos e despesas cadastrados. Valores
        antigos sem cobertura de custos ficam sinalizados; taxas e impostos não
        cadastrados não entram na estimativa.{" "}
        <Link to="/dashboard">Ver dia, semana e mês →</Link>
      </p>
      <form className="management-panel form-columns" onSubmit={submit}>
        <h2 className="span-all">Registrar despesa</h2>
        <label>
          Descrição
          <input name="description" required minLength={2} maxLength={150} />
        </label>
        <label>
          Valor (R$)
          <input
            name="amount"
            required
            inputMode="decimal"
            placeholder="Ex.: 120,50"
          />
        </label>
        <label>
          Data da despesa
          <input name="date" required type="date" defaultValue={today()} />
        </label>
        <label>
          Justificativa
          <input name="reason" required minLength={5} maxLength={500} />
        </label>
        <button className="primary" disabled={busy}>
          {busy ? "Registrando…" : "Registrar despesa"}
        </button>
      </form>
      <article className="management-panel">
        <h2>Despesas do mês até a data escolhida</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Data</th>
                <th>Descrição</th>
                <th>Valor</th>
              </tr>
            </thead>
            <tbody>
              {expenses.map((e) => (
                <tr key={e.id}>
                  <td>{e.expense_date.split("-").reverse().join("/")}</td>
                  <td>{e.description}</td>
                  <td>{money(e.amount_cents)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {!expenses.length && (
            <p>Nenhuma despesa registrada neste intervalo.</p>
          )}
        </div>
      </article>
    </section>
  );
}
