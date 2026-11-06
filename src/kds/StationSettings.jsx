import { useState } from "react";
import { Check, Settings2 } from "lucide-react";
import { rpc } from "../lib/supabase";
import { STATIONS } from "./demand";
export default function StationSettings({ stations }) {
  const [busy, setBusy] = useState(null),
    [error, setError] = useState(""),
    [notice, setNotice] = useState("");
  return (
    <details className="station-settings">
      <summary>
        <Settings2 size={18} /> Ajustar capacidade das praças
      </summary>
      <p>
        Calibre conforme a equipe do turno. Sem histórico, usamos a referência
        inicial; com histórico, a média dos últimos tickets. A estimativa
        considera os itens que já estão em preparo.
      </p>
      {error && <p role="alert" className="error-message">{error}</p>}
      {notice && (
        <p className="success-note" role="status">
          <Check size={17} />
          {notice}
        </p>
      )}
      <div className="station-settings-grid">
        {stations.map((station) => (
          <form
            key={`${station.sector}:${station.parallel_capacity}:${station.critical_items}:${station.reference_unit_seconds}`}
            onSubmit={async (event) => {
              event.preventDefault();
              setBusy(station.sector);
              setError("");
              setNotice("");
              const fields = new FormData(event.currentTarget);
              try {
                await rpc("set_kitchen_station", {
                  p_sector: station.sector,
                  p_seconds: Number(fields.get("seconds")),
                  p_capacity: Number(fields.get("capacity")),
                  p_critical: Number(fields.get("critical")),
                  p_reason: fields.get("reason"),
                });
                setNotice(
                  "Parâmetros salvos. A previsão será atualizada para toda a equipe.",
                );
              } catch (error) {
                setError(error.message);
              } finally {
                setBusy(null);
              }
            }}
          >
            <h3>{STATIONS.find((s) => s.id === station.sector)?.label}</h3>
            <label>
              Segundos por item · referência<input
                name="seconds"
                type="number"
                min="10"
                max="3600"
                required
                defaultValue={station.reference_unit_seconds}
              />
            </label>
            <label>
              Itens preparados em paralelo<input
                name="capacity"
                type="number"
                min="1"
                max="30"
                required
                defaultValue={station.parallel_capacity}
              />
            </label>
            <label>
              Alertar acima de quantos itens?<input
                name="critical"
                type="number"
                min="1"
                max="999"
                required
                defaultValue={station.critical_items}
              />
            </label>
            <label>
              Motivo do ajuste<input
                name="reason"
                required
                minLength={5}
                maxLength={500}
              />
            </label>
            <button className="primary" disabled={busy !== null}>
              {busy === station.sector ? "Salvando…" : "Salvar capacidade"}
            </button>
          </form>
        ))}
      </div>
    </details>
  );
}
