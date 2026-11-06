import { useState, useEffect, useCallback } from "react";
import { supabase } from "../lib/supabase";
import { money } from "../lib/operations";
export default function Audit() {
  const [rows, setRows] = useState([]),
    [action, setAction] = useState(""),
    [error, setError] = useState(""),
    [cursor, setCursor] = useState(null);
  const fetchRows = useCallback(async (filter, before, more = false) => {
    let query = supabase
      .from("audit_log")
      .select(
        "id,actor_id,actor_kind,action,entity_type,entity_key,created_at,amount_cents,quantity_delta,justification",
      )
      .order("id", { ascending: false })
      .limit(100);
    if (filter)
      query = query.ilike("action", `%${filter.replace(/[%_]/g, "")}%`);
    if (before) query = query.lt("id", before);
    const { data, error } = await query;
    if (error) setError("Não foi possível consultar a auditoria.");
    else {
      setRows((previous) => (more ? [...previous, ...data] : data));
      setCursor(data.at(-1)?.id || null);
      setError("");
    }
  }, []);
  const load = (more = false) => fetchRows(action, more ? cursor : null, more);
  useEffect(() => {
    const t = setTimeout(() => fetchRows("", null, false), 0);
    return () => clearTimeout(t);
  }, [fetchRows]);
  return (
    <section className="management">
      <span className="eyebrow">SEGURANÇA E PREVENÇÃO A FRAUDES</span>
      <h1>Trilha de auditoria.</h1>
      <p>
        Somente leitura. Cancelamentos, estornos, sangrias, descontos e
        alterações de estoque são registrados pelo servidor. Não existem ações
        de editar ou apagar estes registros.
      </p>
      <form
        className="filter-row"
        onSubmit={(e) => {
          e.preventDefault();
          load();
        }}
      >
        <label>
          Filtrar ação
          <input
            value={action}
            onChange={(e) => setAction(e.target.value)}
            maxLength={80}
            placeholder="refund, inventory, cash…"
          />
        </label>
        <button className="primary">Consultar</button>
      </form>
      {error && (
        <p role="alert" className="error-message">
          {error}
        </p>
      )}
      <article className="management-panel table-wrap">
        <table>
          <thead>
            <tr>
              <th>Data e hora</th>
              <th>Usuário / origem</th>
              <th>Ação</th>
              <th>Valor</th>
              <th>Qtd. estoque</th>
              <th>Justificativa</th>
              <th>Registro</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <td>{new Date(r.created_at).toLocaleString("pt-BR")}</td>
                <td>{r.actor_id || r.actor_kind}</td>
                <td>{r.action}</td>
                <td>{money(r.amount_cents)}</td>
                <td>{r.quantity_delta ?? "—"}</td>
                <td className="audit-reason">{r.justification}</td>
                <td>
                  {r.entity_type} · {r.entity_key}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </article>
      {cursor && (
        <button className="secondary" onClick={() => load(true)}>
          Carregar mais registros
        </button>
      )}
    </section>
  );
}
