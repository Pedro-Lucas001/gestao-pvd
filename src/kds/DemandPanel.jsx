import {
  Clock3,
  CookingPot,
  CupSoda,
  Flame,
  TriangleAlert,
} from "lucide-react";
import { estimateOrderPreparation, STATIONS } from "./demand";
import { useKitchenDemand } from "./useKitchenDemand";
const icons = { flame: Flame, cooking: CookingPot, cup: CupSoda };
export function DemandSummary(
  { demand, compact = false, items = [], products = [] },
) {
  if (demand.loading) {
    return (
      <div className="demand-loading" role="status">
        Consultando a carga da cozinha…
      </div>
    );
  }
  if (demand.error && !demand.stations.length) {
    return (
      <p className="offline-banner" role="status">
        Demanda indisponível. Confirme o prazo com a cozinha.
      </p>
    );
  }
  const high = demand.stations.filter((station) => station.high);
  const orderMinutes = estimateOrderPreparation(
    demand.stations,
    items,
    products,
  );
  return (
    <section
      className={`demand-panel ${compact ? "compact" : ""}`}
      aria-label="Carga por praça"
    >
      <div className="demand-heading">
        <div>
          <span className="eyebrow">RITMO DA OPERAÇÃO</span>
          <h2>
            {compact ? "Como está a cozinha agora" : "Uma visão de cada praça."}
          </h2>
        </div>
        <span className="demand-estimate-label">
          <Clock3 size={16} /> Estimativa de produção
        </span>
      </div>
      {demand.error && (
        <p className="offline-banner" role="status">
          Exibindo a última leitura. {demand.error}
        </p>
      )}
      <div className="station-load-grid">
        {STATIONS.map(({ id, label, icon }) => {
          const station = demand.stations.find((row) => row.sector === id),
            Icon = icons[icon];
          if (!station) return null;
          return (
            <article
              key={id}
              className={`station-load ${station.high ? "high" : ""}`}
              data-station={id}
            >
              <div className="station-load-title">
                <span>
                  <Icon size={20} />
                  {label}
                </span>
                <span className={`load-badge ${station.high ? "high" : ""}`}>
                  {station.high ? "Alta demanda" : "Fluxo normal"}
                </span>
              </div>
              <div className="station-load-count">
                <strong>{station.items}</strong>
                <span>
                  itens pendentes<br />
                  <small>
                    {station.queued} na fila · {station.preparing} em preparo
                  </small>
                </span>
              </div>
              <div className="station-load-track" aria-hidden="true">
                <i style={{ width: `${station.loadPercent}%` }} />
              </div>
              <div className="station-load-foot">
                <span>
                  Próximo item ≈ <b>{station.nextItemMinutes} min</b>
                </span>
                <small>
                  {station.sampleCount
                    ? `Média medida · ${station.sampleCount} tickets`
                    : "Referência inicial"}
                </small>
              </div>
            </article>
          );
        })}
      </div>
      {high.length > 0 && (
        <div className="demand-alert" role="status">
          <TriangleAlert size={22} />
          <div>
            <strong>
              Alta demanda em{" "}
              {high.map((station) =>
                STATIONS.find((s) => s.id === station.sector)?.label
              ).join(" e ")}.
            </strong>
            <p>
              Avise os próximos clientes: a produção pode levar mais tempo.
              Maior previsão por item: aproximadamente{" "}
              {Math.max(...high.map((station) => station.nextItemMinutes))}{" "}
              min, sem incluir entrega.
            </p>
          </div>
        </div>
      )}
      {orderMinutes !== null && (
        <div className="draft-preparation" role="status">
          <Clock3 size={20} />
          <div>
            <strong>
              Produção deste pedido: aproximadamente {orderMinutes} min
            </strong>
            <p>
              Considera os itens do carrinho e a praça mais lenta. O
              deslocamento da entrega não está incluído.
            </p>
          </div>
        </div>
      )}
      {!compact && (
        <p className="demand-footnote">
          Fila + preparo, média por unidade e capacidade simultânea configurada.
          A estimativa não inclui deslocamento da entrega.
        </p>
      )}
    </section>
  );
}
export default function DemandPanel(
  { compact = false, items = [], products = [] },
) {
  const demand = useKitchenDemand();
  return (
    <DemandSummary
      demand={demand}
      compact={compact}
      items={items}
      products={products}
    />
  );
}
