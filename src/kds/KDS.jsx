import { useCallback, useEffect, useState } from "react";
import {
  CheckCheck,
  ChefHat,
  Clock3,
  CookingPot,
  CupSoda,
  Flame,
  LockKeyhole,
  RefreshCw,
  WifiOff,
} from "lucide-react";
import { rpc, supabase } from "../lib/supabase";
import { urgency } from "../lib/operations";
import { useAuth } from "../auth/context";
import { useConnection } from "../components/useConnection";
import { STATIONS, ticketUnits } from "./demand";
import { useKitchenDemand } from "./useKitchenDemand";
import { DemandSummary } from "./DemandPanel";
import StationSettings from "./StationSettings";
const icons = { grill: Flame, fryer: CookingPot, bar: CupSoda };
const urgencyNames = {
  normal: "No prazo",
  warning: "Atenção ao tempo",
  critical: "Acima de 20 min",
};
export default function KDS() {
  const { profile } = useAuth();
  const online = useConnection(), demand = useKitchenDemand();
  const [tickets, setTickets] = useState([]),
    [connection, setConnection] = useState("reconnecting"),
    [error, setError] = useState(""),
    [now, setNow] = useState(Date.now),
    [busy, setBusy] = useState(null),
    [loading, setLoading] = useState(true),
    [version, setVersion] = useState(0),
    [filter, setFilter] = useState("all");
  const selected = profile.role === "kitchen" ? profile.sector : filter;
  const refresh = useCallback(() => setVersion((v) => v + 1), []);
  useEffect(() => {
    let alive = true;
    const abort = new AbortController();
    async function load() {
      let query = supabase.from("kitchen_tickets").select(
        "id,order_number,sector,items,status,created_at,started_at",
      )
        .not("status", "in", "(ready,cancelled)").order("created_at");
      if (profile.role === "kitchen") {
        query = query.eq("sector", profile.sector);
      }
      const { data, error } = await query.abortSignal(abort.signal);
      if (!alive) return;
      if (error) {
        setError("Não foi possível sincronizar a cozinha. Confira a conexão.");
      } else {
        setTickets(data || []);
        setError("");
      }
      setLoading(false);
    }
    const timer = setTimeout(load, 0);
    return () => {
      alive = false;
      clearTimeout(timer);
      abort.abort();
    };
  }, [profile.role, profile.sector, version]);
  useEffect(() => {
    let alive = true;
    const channel = supabase.channel(`kds:${profile.id}`).on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "kitchen_tickets",
        ...(profile.role === "kitchen"
          ? { filter: `sector=eq.${profile.sector}` }
          : {}),
      },
      refresh,
    ).subscribe((status) => {
      if (!alive) return;
      setConnection(status === "SUBSCRIBED" ? "connected" : "reconnecting");
      if (status === "SUBSCRIBED") refresh();
    });
    const clock = setInterval(() => setNow(Date.now()), 1000);
    const poll = setInterval(() => {
      if (navigator.onLine) refresh();
    }, 10000);
    window.addEventListener("online", refresh);
    return () => {
      alive = false;
      clearInterval(clock);
      clearInterval(poll);
      window.removeEventListener("online", refresh);
      supabase.removeChannel(channel);
    };
  }, [profile.id, profile.role, profile.sector, refresh]);
  async function advance(ticket) {
    if (busy) return;
    setBusy(ticket.id);
    try {
      await rpc("update_ticket", {
        p_ticket: ticket.id,
        p_status: ticket.status === "queued" ? "preparing" : "ready",
      });
      refresh();
    } catch (error) {
      setError(error.message);
    } finally {
      setBusy(null);
    }
  }
  const visible = tickets.filter((ticket) =>
    selected === "all" || ticket.sector === selected
  );
  return (
    <section className="kds-page">
      <div className="pdv-heading">
        <div>
          <span className="eyebrow">COZINHA · OPERAÇÃO EM TEMPO REAL</span>
          <h1>
            Cada praça no seu ritmo<span className="heading-dot">.</span>
          </h1>
          <p>
            O pedido certo, na praça certa. Do primeiro preparo à última
            entrega.
          </p>
        </div>
        <span className={`connection-state ${connection}`}>
          <span className="live-dot" />
          {connection === "connected"
            ? "Realtime conectado"
            : "Reconectando · consulta a cada 10 s"}
        </span>
      </div>
      <DemandSummary demand={demand} />
      {profile.role === "admin" && demand.stations.length > 0 && (
        <StationSettings stations={demand.stations} />
      )}
      <div className="kds-toolbar">
        <div
          className="station-tabs"
          role="tablist"
          aria-label="Filtrar pedidos por praça"
        >
          {profile.role === "admin" && (
            <button
              role="tab"
              aria-selected={selected === "all"}
              className={selected === "all" ? "active" : ""}
              onClick={() => setFilter("all")}
            >
              <ChefHat size={19} />Todas as praças<span>{tickets.length}</span>
            </button>
          )}
          {STATIONS.map((station) => {
            const Icon = icons[station.id],
              forbidden = profile.role === "kitchen" &&
                station.id !== profile.sector;
            return (
              <button
                role="tab"
                key={station.id}
                disabled={forbidden}
                aria-selected={selected === station.id}
                className={selected === station.id ? "active" : ""}
                onClick={() => setFilter(station.id)}
              >
                <Icon size={19} />
                {station.label}
                {forbidden ? <LockKeyhole size={15} /> : (
                  <span>
                    {tickets.filter((t) => t.sector === station.id).length}
                  </span>
                )}
              </button>
            );
          })}
        </div>
        <div className="kds-time-legend">
          <span className="normal">0–10 min</span>
          <span className="warning">10–20 min</span>
          <span className="critical">Mais de 20 min</span>
        </div>
      </div>
      {(!online || connection !== "connected") && (
        <div className="offline-banner" role="status">
          <WifiOff size={18} />
          {online
            ? "Reconectando e ressincronizando. Os últimos cartões continuam visíveis."
            : "Sem internet. Cartões podem estar desatualizados; ações bloqueadas."}
        </div>
      )}
      {error && (
        <div className="error-message" role="alert">
          {error}
          <button className="secondary" onClick={refresh}>
            <RefreshCw size={17} />Tentar novamente
          </button>
        </div>
      )}
      <div className="kds-list-heading">
        <h2>
          {selected === "all"
            ? "Pedidos em produção"
            : STATIONS.find((s) => s.id === selected)?.label}
        </h2>
        <span>
          {visible.length} {visible.length === 1 ? "comanda" : "comandas"} ·
          {" "}
          {visible.reduce((sum, t) => sum + ticketUnits(t), 0)} itens
        </span>
      </div>
      <div
        className="kds-grid"
        role="tabpanel"
        aria-label="Pedidos da praça selecionada"
        aria-busy={loading}
      >
        {visible.map((ticket) => {
          const age = urgency(ticket.created_at, now),
            Icon = icons[ticket.sector] || ChefHat;
          return (
            <article
              className={`kds-card ${age}`}
              key={ticket.id}
              data-ticket={ticket.id}
            >
              <div className="kds-top">
                <strong>#{String(ticket.order_number).padStart(4, "0")}</strong>
                <span className={`urgency-tag ${age}`}>
                  <Clock3 size={16} />
                  {Math.max(
                    0,
                    Math.floor(
                      (now - new Date(ticket.created_at).getTime()) / 60000,
                    ),
                  )} min
                </span>
              </div>
              <div className="kds-card-status">
                <span>
                  <Icon size={16} />
                  {STATIONS.find((s) => s.id === ticket.sector)?.label}
                </span>
                <b>{ticket.status === "queued" ? "Na fila" : "Em preparo"}</b>
              </div>
              <p className="kds-urgency-label">{urgencyNames[age]}</p>
              <ul>
                {ticket.items.map((item, index) => (
                  <li key={index}>
                    <b>{item.quantity}×</b>
                    <div>
                      <strong>{item.name}</strong>
                      {item.modifiers?.map((modifier) => (
                        <small key={modifier}>{modifier}</small>
                      ))}
                      {item.notes && <p>{item.notes}</p>}
                    </div>
                  </li>
                ))}
              </ul>
              <button
                className="primary full"
                disabled={!online || busy !== null}
                onClick={() => advance(ticket)}
              >
                {busy === ticket.id
                  ? "Confirmando…"
                  : ticket.status === "queued"
                  ? (
                    <>
                      <Flame size={19} />Iniciar preparo
                    </>
                  )
                  : (
                    <>
                      <CheckCheck size={19} />Pronto neste setor
                    </>
                  )}
              </button>
            </article>
          );
        })}
      </div>
      {loading && (
        <div className="empty" role="status">
          <RefreshCw size={32} />
          <h2>Sincronizando a cozinha…</h2>
        </div>
      )}
      {!loading && !visible.length && !error && (
        <div className="empty">
          <ChefHat size={42} />
          <h2>Nenhum pedido neste setor.</h2>
          <p>Pedidos com pagamento confirmado aparecem aqui automaticamente.</p>
        </div>
      )}
    </section>
  );
}
