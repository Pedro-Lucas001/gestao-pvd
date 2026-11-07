import { useEffect, useState } from "react";
import { rpc } from "../lib/supabase";
import { STATIONS } from "./demand";
import "../admin/OnlineOrders.css";
const sectorLabel = (s) => STATIONS.find((x) => x.id === s)?.label || s;
function Items({ items }) {
  return (
    <ul className="online-lines">
      {(items || []).map((i, n) => (
        <li key={n}>
          <strong>
            {i.quantity}× {i.name}
          </strong>
          {i.modifiers?.length > 0 && <p>{i.modifiers.join(" · ")}</p>}
          {i.notes && <p>{i.notes}</p>}
        </li>
      ))}
    </ul>
  );
}
function Review({ change, run, busy }) {
  const [reason, setReason] = useState("");
  return (
    <article className="online-card online-review">
      <h3>Alteração · Online #{change.number}</h3>
      <p>
        <strong>Solicitação:</strong> {change.reason}
      </p>
      <p>
        Proposta completa para seu setor. Confira o que já foi produzido antes
        de aprovar. O preparo fica pausado até a decisão.
      </p>
      <Items items={change.items} />
      <small>
        Aprovações:{" "}
        {change.approved_sectors.map(sectorLabel).join(", ") || "Nenhuma"}.
        Setores necessários: {change.sectors.map(sectorLabel).join(", ")}.
      </small>
      <label>
        Retorno ao cliente
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          minLength={5}
          maxLength={500}
          placeholder="Explique a decisão e a viabilidade no preparo."
        />
      </label>
      <div className="online-actions">
        <button
          className="primary"
          disabled={busy || reason.trim().length < 5}
          onClick={() =>
            run("online_review_change", {
              p_change: change.id,
              p_accept: true,
              p_reason: reason,
            })
          }
        >
          Aprovar para meu setor
        </button>
        <button
          className="secondary"
          disabled={busy || reason.trim().length < 5}
          onClick={() =>
            run("online_review_change", {
              p_change: change.id,
              p_accept: false,
              p_reason: reason,
            })
          }
        >
          Recusar alteração
        </button>
      </div>
    </article>
  );
}
export default function OnlineKitchen() {
  const [data, setData] = useState({ orders: [], changes: [] }),
    [error, setError] = useState(""),
    [version, setVersion] = useState(0),
    [busy, setBusy] = useState(false);
  useEffect(() => {
    let alive = true,
      running = false;
    async function load() {
      if (running) return;
      running = true;
      try {
        const d = await rpc("online_kitchen_queue");
        if (alive) {
          setData(d);
          setError("");
        }
      } catch (e) {
        if (alive) setError(e.message);
      } finally {
        running = false;
      }
    }
    const t = setTimeout(load, 0),
      i = setInterval(load, 5000);
    return () => {
      alive = false;
      clearTimeout(t);
      clearInterval(i);
    };
  }, [version]);
  async function run(name, args) {
    setBusy(true);
    setError("");
    try {
      await rpc(name, args);
      setVersion((v) => v + 1);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="online-kitchen">
      <div className="online-heading">
        <div>
          <span className="eyebrow">PEDIDOS DO SITE</span>
          <h2>Cozinha online</h2>
          <p>Atualização a cada 5 segundos. A fila do balcão aparece abaixo.</p>
        </div>
        <button className="secondary" onClick={() => setVersion((v) => v + 1)}>
          Atualizar
        </button>
      </div>
      {error && (
        <p role="alert" className="online-error">
          {error}
        </p>
      )}
      <div className="online-grid">
        {data.changes.map((c) => (
          <Review key={c.id} change={c} run={run} busy={busy} />
        ))}
        {data.orders.map((o) => (
          <article className="online-card" key={`${o.id}:${o.sector}`}>
            <h3>
              Online #{o.number} · {sectorLabel(o.sector)}
            </h3>
            <p>
              {o.fulfillment === "delivery" ? "Entrega" : "Retirada"} ·{" "}
              {o.job_status === "queued" ? "Na fila" : "Em preparo"} · Revisão{" "}
              {o.revision}
            </p>
            {o.change_note && (
              <p className="online-notice">
                Pedido revisado: {o.change_note}. Preserve o que já foi
                produzido e confira a diferença aprovada.
              </p>
            )}
            <Items items={o.items} />
            <button
              className="primary"
              disabled={busy || data.changes.some((c) => c.number === o.number)}
              onClick={() =>
                run("online_kitchen_work", {
                  p_order: o.id,
                  p_sector: o.sector,
                  p_revision: o.revision,
                  p_next: o.job_status === "queued" ? "preparing" : "ready",
                })
              }
            >
              {o.job_status === "queued"
                ? "Iniciar preparo"
                : "Pronto neste setor"}
            </button>
          </article>
        ))}
      </div>
      {!data.orders.length && !data.changes.length && !error && (
        <p className="online-empty">
          Nenhum pedido online liberado ou alteração aguardando análise neste
          setor.
        </p>
      )}
    </section>
  );
}
