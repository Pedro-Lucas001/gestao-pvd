import { useEffect, useState, useCallback } from "react";
import { ChefHat, RefreshCw, WifiOff, Clock3 } from "lucide-react";
import { supabase, rpc } from "../lib/supabase";
import { urgency } from "../lib/operations";
import { useAuth } from "../auth/context";
import { useConnection } from "../components/useConnection";
const sectors = { grill: "Chapa", fryer: "Fritura", bar: "Bebidas" };
export default function KDS() {
  const { profile } = useAuth();
  const online = useConnection();
  const [tickets, setTickets] = useState([]),
    [connection, setConnection] = useState("reconnecting"),
    [error, setError] = useState(""),
    [now, setNow] = useState(() => Date.now()),
    [busy, setBusy] = useState(null);
  const refresh = useCallback(async () => {
    let query = supabase
      .from("kitchen_tickets")
      .select("id,order_number,customer,sector,items,status,created_at")
      .not("status", "in", "(ready,cancelled)")
      .order("created_at");
    if (profile.role === "kitchen") query = query.eq("sector", profile.sector);
    const { data, error } = await query;
    if (error) {
      setError("Não foi possível sincronizar a cozinha. Confira a conexão.");
      return;
    }
    setTickets(data);
    setError("");
  }, [profile.role, profile.sector]);
  useEffect(() => {
    let alive = true;
    const sync = () => {
      if (alive) refresh();
    };
    const start = setTimeout(sync, 0);
    const channel = supabase
      .channel(`kds:${profile.id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "kitchen_tickets",
          ...(profile.role === "kitchen"
            ? { filter: `sector=eq.${profile.sector}` }
            : {}),
        },
        sync,
      )
      .subscribe((status) => {
        if (!alive) return;
        setConnection(status === "SUBSCRIBED" ? "connected" : "reconnecting");
        if (status === "SUBSCRIBED") sync();
      });
    const timer = setInterval(() => {
      setNow(Date.now());
      if (navigator.onLine) sync();
    }, 10000);
    window.addEventListener("online", sync);
    return () => {
      alive = false;
      clearTimeout(start);
      clearInterval(timer);
      window.removeEventListener("online", sync);
      supabase.removeChannel(channel);
    };
  }, [refresh, profile.id, profile.role, profile.sector]);
  async function advance(ticket) {
    setBusy(ticket.id);
    try {
      await rpc("update_ticket", {
        p_ticket: ticket.id,
        p_status: ticket.status === "queued" ? "preparing" : "ready",
      });
      await refresh();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(null);
    }
  }
  return (
    <>
      <div className="pdv-heading">
        <div>
          <span className="eyebrow">
            COZINHA ·{" "}
            {profile.role === "admin"
              ? "TODOS OS SETORES"
              : sectors[profile.sector]}
          </span>
          <h1>
            Cada minuto conta<span className="heading-dot">.</span>
          </h1>
          <p>Verde até 8 min · amarelo de 8 a 15 min · vermelho após 15 min.</p>
        </div>
        <span className={`connection-state ${connection}`}>
          <span className="live-dot" />
          {connection === "connected"
            ? "Realtime conectado"
            : "Reconectando · consulta a cada 10 s"}
        </span>
      </div>
      {(!online || connection !== "connected") && (
        <div className="offline-banner" role="status">
          <WifiOff size={17} />
          {online
            ? "Reconectando e ressincronizando. A confirmação de ações exige conexão."
            : "Sem internet. Os cartões podem estar desatualizados; ações bloqueadas."}
        </div>
      )}
      {error && (
        <div className="error-message" role="alert">
          {error}
          <button className="secondary" onClick={refresh}>
            <RefreshCw size={14} />
            Tentar novamente
          </button>
        </div>
      )}
      <div className="kds-grid">
        {tickets.map((t) => (
          <article
            className={`kds-card ${urgency(t.created_at, now)}`}
            key={t.id}
          >
            <div className="kds-top">
              <strong>#{String(t.order_number).padStart(4, "0")}</strong>
              <span>
                <Clock3 size={13} />
                {Math.max(
                  0,
                  Math.floor((now - new Date(t.created_at).getTime()) / 60000),
                )}{" "}
                min
              </span>
            </div>
            <h2>{t.customer}</h2>
            <span className="kds-sector">
              {sectors[t.sector]} ·{" "}
              {t.status === "queued" ? "Na fila" : "Em preparo"}
            </span>
            <ul>
              {t.items.map((i, index) => (
                <li key={index}>
                  <b>{i.quantity}×</b>
                  <div>
                    <strong>{i.name}</strong>
                    {i.modifiers?.map((m) => (
                      <small key={m}>{m}</small>
                    ))}
                    {i.notes && <p>{i.notes}</p>}
                  </div>
                </li>
              ))}
            </ul>
            <button
              className="primary full"
              disabled={!online || busy === t.id}
              onClick={() => advance(t)}
            >
              {t.status === "queued" ? "Iniciar preparo" : "Pronto neste setor"}
            </button>
          </article>
        ))}
      </div>
      {!tickets.length && !error && (
        <div className="empty">
          <ChefHat size={40} />
          <h2>Nenhum pedido neste setor.</h2>
          <p>Somente pagamentos confirmados liberam novos pedidos.</p>
        </div>
      )}
    </>
  );
}
