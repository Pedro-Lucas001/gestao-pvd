import { useCallback, useEffect, useState } from "react";
import {
  ChefHat,
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
import OperationalBrand from "../design/OperationalBrand";
import OrderTicketCard from "./OrderTicketCard";
const icons = { grill: Flame, fryer: CookingPot, bar: CupSoda };
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
    <section className="pl-kds pl:min-h-screen pl:min-w-0 pl:bg-[#1a1a1a] pl:font-sans pl:text-gray-100">
      <div className="pdv-heading pl:flex pl:flex-wrap pl:items-center pl:justify-between pl:gap-4">
        <OperationalBrand title="Cozinha · KDS" />
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
      <div className="kds-toolbar pl:rounded-xl pl:bg-[#2d2d2d] pl:px-4 pl:py-4">
        <div
          className="station-tabs pl:flex pl:flex-nowrap pl:gap-3 pl:overflow-x-auto pl:pb-2"
          role="tablist"
          aria-label="Filtrar pedidos por praça"
        >
          {profile.role === "admin" && (
            <button
              role="tab"
              aria-selected={selected === "all"}
              className={`pl:flex pl:min-h-12 pl:shrink-0 pl:items-center pl:gap-2 pl:rounded-full pl:whitespace-nowrap pl:border-0 pl:px-6 pl:py-2 pl:text-sm pl:font-semibold pl:transition-colors ${
                selected === "all"
                  ? "active pl:bg-[#ff5722] pl:text-white"
                  : "pl:bg-[#1a1a1a] pl:text-gray-300 pl:hover:bg-[#3d3d3d]"
              }`}
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
                className={`pl:flex pl:min-h-12 pl:shrink-0 pl:items-center pl:gap-2 pl:rounded-full pl:whitespace-nowrap pl:border-0 pl:px-6 pl:py-2 pl:text-sm pl:font-semibold pl:transition-colors ${
                  selected === station.id
                    ? "active pl:bg-[#ff5722] pl:text-white"
                    : "pl:bg-[#1a1a1a] pl:text-gray-300 pl:hover:bg-[#3d3d3d]"
                }`}
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
        className="kds-grid pl:grid pl:grid-cols-1 pl:items-stretch pl:gap-4 pl:md:grid-cols-2 pl:xl:grid-cols-3 pl:2xl:grid-cols-4"
        role="tabpanel"
        aria-label="Pedidos da praça selecionada"
        aria-busy={loading}
      >
        {visible.map((ticket) => (
          <OrderTicketCard
            key={ticket.id}
            ticket={ticket}
            urgency={urgency(ticket.created_at, now)}
            now={now}
            busy={busy === ticket.id}
            disabled={!online || busy !== null}
            onAdvance={advance}
          />
        ))}
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
