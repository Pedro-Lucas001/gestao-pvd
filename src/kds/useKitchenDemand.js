import { useEffect, useId, useState } from "react";
import { rpc, supabase } from "../lib/supabase";
import { calculateDemand } from "./demand";
export function useKitchenDemand(enabled = true) {
  const channelId = useId();
  const [state, setState] = useState({
    stations: [],
    loading: true,
    error: "",
    connected: false,
    updatedAt: null,
  });
  useEffect(() => {
    if (!enabled || !supabase) return;
    let alive = true, inFlight = false, pending = false;
    async function sync() {
      if (!alive) return;
      if (inFlight) {
        pending = true;
        return;
      }
      inFlight = true;
      try {
        const rows = await rpc("kitchen_load_snapshot");
        if (!Array.isArray(rows)) throw new Error("INVALID_DEMAND_RESPONSE");
        if (alive) {
          setState((previous) => ({
            ...previous,
            stations: rows.map(calculateDemand),
            loading: false,
            error: "",
            updatedAt: Date.now(),
          }));
        }
      } catch {
        if (alive) {
          setState((previous) => ({
            ...previous,
            loading: false,
            error: "Não foi possível atualizar a demanda. Confira a conexão.",
          }));
        }
      } finally {
        inFlight = false;
        if (alive && pending) {
          pending = false;
          sync();
        }
      }
    }
    const start = setTimeout(sync, 0);
    const channel = supabase.channel(`station-load:${channelId}`).on(
      "postgres_changes",
      { event: "*", schema: "public", table: "kitchen_station_load" },
      sync,
    ).subscribe((status) => {
      if (alive) {
        setState((previous) => ({
          ...previous,
          connected: status === "SUBSCRIBED",
        }));
      }
      if (status === "SUBSCRIBED") sync();
    });
    const timer = setInterval(() => {
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
  }, [enabled, channelId]);
  return state;
}
