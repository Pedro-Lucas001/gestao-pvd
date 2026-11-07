import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  ArrowUpRight,
  Boxes,
  CalendarDays,
  CircleDollarSign,
  PackagePlus,
  RefreshCw,
  Users,
} from "lucide-react";
import { rpc } from "../lib/supabase";
import { money } from "../lib/operations";
import "./AdminControl.css";
function shopToday(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Recife",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}
function Metric({ label, value, note, accent = false }) {
  return (
    <article className={`control-metric ${accent ? "accent" : ""}`}>
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{note}</small>
    </article>
  );
}
export function DashboardView({
  data,
  reference,
  setReference,
  period,
  setPeriod,
  refresh,
  busy,
  error,
}) {
  const p = data?.periods[period];
  const daily = data?.daily || [],
    highest = Math.max(1, ...daily.map((d) => Number(d.received_cents))),
    width = Math.max(1, daily.length) * 24;
  return (
    <section className="control-dashboard">
      <header className="control-heading">
        <div>
          <span className="eyebrow">VISÃO DA ADMINISTRAÇÃO</span>
          <h1>Seu Planeta sob controle.</h1>
          <p>
            Recebimentos do balcão e do site, estoque e equipe no mesmo lugar.
          </p>
        </div>
        <button className="secondary" disabled={busy} onClick={refresh}>
          <RefreshCw size={16} />
          {busy ? "Atualizando…" : "Atualizar"}
        </button>
      </header>
      <nav className="control-shortcuts" aria-label="Ações da administração">
        {[
          ["/catalogo", "Produtos e fotos", PackagePlus],
          ["/estoque", "Estoque e fichas", Boxes],
          ["/equipe", "Equipe e PINs", Users],
          ["/pedidos-online", "Pedidos online", CircleDollarSign],
        ].map(([path, label, Icon]) => (
          <Link key={path} to={path}>
            <Icon size={20} />
            <span>{label}</span>
            <ArrowUpRight size={17} />
          </Link>
        ))}
      </nav>
      <div className="control-period-bar">
        <div
          className="control-periods"
          role="group"
          aria-label="Período dos resultados"
        >
          {[
            ["day", "Dia"],
            ["week", "Semana"],
            ["month", "Mês"],
          ].map(([key, label]) => (
            <button
              type="button"
              key={key}
              aria-pressed={period === key}
              onClick={() => setPeriod(key)}
            >
              {label}
            </button>
          ))}
        </div>
        <label>
          <CalendarDays size={17} />
          Data de referência
          <input
            type="date"
            value={reference}
            max={shopToday()}
            onChange={(e) => e.target.value && setReference(e.target.value)}
          />
        </label>
      </div>
      {error && (
        <p role="alert" className="error-message">
          {error}
        </p>
      )}
      {busy && !data && <p role="status">Consultando indicadores reais…</p>}
      {data && p && (
        <>
          <p className="control-period-note">
            {p.from.split("-").reverse().join("/")} a{" "}
            {p.to.split("-").reverse().join("/")} · Horário de Recife · Semana
            de segunda-feira até a data escolhida.
          </p>
          <div className="control-metrics">
            <Metric
              label="Recebido no período"
              value={money(p.received_cents)}
              note={`${p.paid_orders} pedidos com recebimento confirmado`}
            />
            <Metric
              label="Recebido após devoluções"
              value={money(p.net_received_cents)}
              note={`${money(p.refunds_cents)} devolvidos no período`}
            />
            <Metric
              label="Custo dos insumos baixados"
              value={money(p.cost_cents)}
              note="Custo registrado no momento do consumo"
            />
            <Metric
              label="Resultado operacional estimado"
              value={
                p.result_cents === null
                  ? "Custos incompletos"
                  : money(p.result_cents)
              }
              note={
                p.result_cents === null
                  ? "Complete as fichas para as próximas vendas."
                  : `Após ${money(p.expenses_cents)} em despesas registradas`
              }
              accent
            />
          </div>
          {p.incomplete_cost_orders > 0 && (
            <p className="control-notice" role="status">
              Há {p.incomplete_cost_orders} pedidos com custos não comprovados
              ou ficha ausente. O resultado fica indisponível para não
              apresentar lucro sem os custos. Histórico anterior não é
              recalculado pelo custo atual.{" "}
              <Link to="/estoque">Conferir fichas técnicas</Link>
            </p>
          )}
          <div className="control-columns">
            <article className="control-panel">
              <header>
                <div>
                  <span className="eyebrow">ACOMPANHAMENTO DO MÊS</span>
                  <h2>Entradas confirmadas por dia</h2>
                </div>
              </header>
              <div className="control-chart">
                <svg
                  viewBox={`0 0 ${width} 130`}
                  role="img"
                  aria-label="Recebimentos confirmados por dia do mês, detalhados na tabela abaixo"
                >
                  {daily.map((d, i) => (
                    <g key={d.date}>
                      <title>
                        {d.date}: {money(d.received_cents)} recebidos;{" "}
                        {money(d.refunds_cents)} devolvidos
                      </title>
                      <rect
                        className="control-chart-track"
                        x={i * 24 + 4}
                        y="0"
                        width="14"
                        height="110"
                        rx="4"
                      />
                      <rect
                        className="control-chart-value"
                        x={i * 24 + 4}
                        y={110 - (Number(d.received_cents) / highest) * 108}
                        width="14"
                        height={Math.max(
                          1,
                          (Number(d.received_cents) / highest) * 108,
                        )}
                        rx="4"
                      />
                      <text x={i * 24 + 11} y="126" textAnchor="middle">
                        {Number(d.date.slice(-2))}
                      </text>
                    </g>
                  ))}
                </svg>
              </div>
              <details>
                <summary>Ver valores por dia</summary>
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Dia</th>
                        <th>Recebido</th>
                        <th>Devolvido</th>
                      </tr>
                    </thead>
                    <tbody>
                      {daily.map((d) => (
                        <tr key={d.date}>
                          <td>{d.date.split("-").reverse().join("/")}</td>
                          <td>{money(d.received_cents)}</td>
                          <td>{money(d.refunds_cents)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </details>
            </article>
            <article className="control-panel">
              <span className="eyebrow">ORIGEM DOS RECEBIMENTOS</span>
              <h2>De onde vieram as vendas</h2>
              <div className="control-total-row">
                <span>Balcão e links anteriores</span>
                <strong>{money(p.pos_received_cents)}</strong>
              </div>
              <div className="control-total-row">
                <span>Pedidos novos do site</span>
                <strong>{money(p.online_received_cents)}</strong>
              </div>
              <hr />
              <div className="control-total-row">
                <span>Despesas registradas</span>
                <strong>{money(p.expenses_cents)}</strong>
              </div>
              <Link className="text-button" to="/dre">
                Registrar despesas e conferir resultado →
              </Link>
              <p className="control-muted">
                Movimentos por data de confirmação, devolução, consumo e
                despesa. Taxas de cartão, impostos e custos que não foram
                cadastrados não estão incluídos. É uma estimativa gerencial.
              </p>
            </article>
          </div>
          <div className="control-section-heading">
            <div>
              <span className="eyebrow">POSIÇÃO ATUAL</span>
              <h2>Controle de estoque</h2>
            </div>
            <Link to="/estoque">Gerenciar insumos →</Link>
          </div>
          <div className="control-metrics stock-metrics">
            <Metric
              label="Insumos cadastrados"
              value={data.inventory.count}
              note="Saldos nas unidades de cada insumo"
            />
            <Metric
              label="No mínimo ou abaixo"
              value={data.inventory.low_count}
              note={`${data.inventory.negative_count} com saldo negativo`}
            />
            <Metric
              label="Valor do estoque positivo"
              value={money(data.inventory.value_cents)}
              note="Estimativa pelo custo atual cadastrado"
            />
            <Metric
              label="A receber de pedidos aceitos"
              value={money(data.receivable_cents)}
              note={`${data.open_shifts} turnos abertos · posição atual`}
            />
          </div>
          <article className="control-panel">
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Insumo</th>
                    <th>Saldo atual</th>
                    <th>Mínimo</th>
                    <th>Situação</th>
                  </tr>
                </thead>
                <tbody>
                  {data.inventory.items.slice(0, 12).map((i) => (
                    <tr key={i.id}>
                      <td>{i.name}</td>
                      <td>
                        {Number(i.stock).toLocaleString("pt-BR")} {i.unit}
                      </td>
                      <td>
                        {Number(i.minimum_stock).toLocaleString("pt-BR")}{" "}
                        {i.unit}
                      </td>
                      <td>
                        <span
                          className={`control-badge ${Number(i.stock) <= Number(i.minimum_stock) ? "warning" : "ok"}`}
                        >
                          {Number(i.stock) < 0
                            ? "Saldo negativo"
                            : Number(i.stock) <= Number(i.minimum_stock)
                              ? "Repor estoque"
                              : "Em dia"}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {!data.inventory.items.length && (
              <p>
                Cadastre os insumos e as fichas técnicas para acompanhar o
                estoque e o custo dos produtos.
              </p>
            )}
            {data.inventory.count > 12 && (
              <Link to="/estoque">Ver todos os insumos →</Link>
            )}
          </article>
        </>
      )}
    </section>
  );
}
export default function AdminDashboard() {
  const [reference, setReference] = useState(shopToday),
    [period, setPeriod] = useState("day"),
    [data, setData] = useState(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(true),
    [version, setVersion] = useState(0);
  const refresh = useCallback(() => setVersion((v) => v + 1), []);
  useEffect(() => {
    let alive = true;
    async function load() {
      setBusy(true);
      setError("");
      try {
        const result = await rpc("admin_control_snapshot", {
          p_reference: reference,
        });
        if (alive) setData(result);
      } catch (e) {
        if (alive) {
          setError(e.message);
          setData(null);
        }
      } finally {
        if (alive) setBusy(false);
      }
    }
    const t = setTimeout(load, 0);
    return () => {
      alive = false;
      clearTimeout(t);
    };
  }, [reference, version]);
  return (
    <DashboardView
      {...{
        data,
        reference,
        setReference,
        period,
        setPeriod,
        refresh,
        busy,
        error,
      }}
    />
  );
}
