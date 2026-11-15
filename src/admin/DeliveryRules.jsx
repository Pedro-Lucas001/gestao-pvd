import { useEffect, useState } from "react";
import { cents } from "../lib/operations";
import { rpc } from "../lib/supabase";

const weekdays = [
  "Segunda",
  "Terça",
  "Quarta",
  "Quinta",
  "Sexta",
  "Sábado",
  "Domingo",
];
const errors = {
  invalid_online_hours: "Confira os horários de abertura e fechamento.",
  invalid_delivery_areas:
    "Confira os bairros e as taxas. O limite por taxa é R$ 1.000,00.",
  duplicate_delivery_area: "Cada bairro deve aparecer uma única vez.",
  delivery_areas_empty: "Adicione um bairro antes de restringir as entregas.",
};

function RulesForm({ config }) {
  const [days, setDays] = useState(() =>
    config.weekly_hours.map((day) => ({
      open: Boolean(day),
      opens: day?.opens ?? "18:00",
      closes: day?.closes ?? "23:00",
    })),
  );
  const [areas, setAreas] = useState(() =>
    config.delivery_areas.map((area) => ({
      ...area,
      fee: (area.fee_cents / 100).toFixed(2),
    })),
  );
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  function updateDay(index, change) {
    setDays((current) =>
      current.map((day, i) => (i === index ? { ...day, ...change } : day)),
    );
  }

  function updateArea(id, change) {
    setAreas((current) =>
      current.map((area) => (area.id === id ? { ...area, ...change } : area)),
    );
  }

  async function save(event) {
    event.preventDefault();
    setMessage("");
    setError("");
    if (busy) return;
    const form = new FormData(event.currentTarget);
    setBusy(true);
    try {
      await rpc("online_save_delivery_rules", {
        p_schedule: form.has("schedule"),
        p_hours: days.map(({ open, opens, closes }) =>
          open ? { opens, closes } : null,
        ),
        p_restrict_areas: form.has("restrict"),
        p_areas: areas.map(({ id, name, fee }) => ({
          id,
          name,
          fee_cents: cents(fee),
        })),
        p_reason: form.get("reason"),
      });
      setMessage("Horários e áreas de entrega salvos.");
    } catch (e) {
      setError(errors[e.message] ?? e.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={save}>
      <fieldset className="online-rules" disabled={busy}>
        <legend>Horários para pedidos online</legend>
        <label className="online-check">
          <input
            type="checkbox"
            name="schedule"
            defaultChecked={config.schedule_enabled}
          />
          Aceitar pedidos somente nos horários abaixo
        </label>
        <p>
          Horário de Recife. Um fechamento anterior à abertura vale para o dia
          seguinte.
        </p>
        {days.map((day, index) => (
          <div className="online-rule-row" key={weekdays[index]}>
            <label className="online-check">
              <input
                type="checkbox"
                checked={day.open}
                onChange={(e) => updateDay(index, { open: e.target.checked })}
              />
              {weekdays[index]}
            </label>
            <label>
              Abertura
              <input
                aria-label={`Abertura de ${weekdays[index]}`}
                type="time"
                required
                disabled={!day.open}
                value={day.opens}
                onChange={(e) => updateDay(index, { opens: e.target.value })}
              />
            </label>
            <label>
              Fechamento
              <input
                aria-label={`Fechamento de ${weekdays[index]}`}
                type="time"
                required
                disabled={!day.open}
                value={day.closes}
                onChange={(e) => updateDay(index, { closes: e.target.value })}
              />
            </label>
          </div>
        ))}
      </fieldset>

      <fieldset className="online-rules" disabled={busy}>
        <legend>Bairros atendidos</legend>
        <label className="online-check">
          <input
            type="checkbox"
            name="restrict"
            defaultChecked={config.delivery_areas_enabled}
          />
          Entregar somente nos bairros cadastrados
        </label>
        <p>
          Com a restrição desligada, vale a taxa fixa das configurações gerais.
          Para entrega grátis, informe 0,00.
        </p>
        {areas.map((area) => (
          <div className="online-rule-row" key={area.id}>
            <label>
              Bairro
              <input
                required
                minLength={2}
                maxLength={80}
                value={area.name}
                onChange={(e) => updateArea(area.id, { name: e.target.value })}
              />
            </label>
            <label>
              Taxa (R$)
              <input
                required
                inputMode="decimal"
                value={area.fee}
                onChange={(e) => updateArea(area.id, { fee: e.target.value })}
              />
            </label>
            <button
              type="button"
              className="secondary"
              onClick={() =>
                setAreas((current) =>
                  current.filter((entry) => entry.id !== area.id),
                )
              }
            >
              Remover
              <span className="online-rule-name">
                {area.name ? ` ${area.name}` : ""}
              </span>
            </button>
          </div>
        ))}
        <button
          type="button"
          className="secondary"
          disabled={areas.length >= 100}
          onClick={() => {
            const area = {
              id: crypto.randomUUID(),
              name: "",
              fee: (config.delivery_fee_cents / 100).toFixed(2),
            };
            setAreas((current) => [...current, area]);
          }}
        >
          Adicionar bairro
        </button>
      </fieldset>

      <label>
        Justificativa
        <input
          name="reason"
          required
          minLength={5}
          maxLength={500}
          disabled={busy}
        />
      </label>
      <button className="primary" disabled={busy}>
        {busy ? "Salvando…" : "Salvar horários e bairros"}
      </button>
      {message && <p role="status">{message}</p>}
      {error && (
        <p className="online-error" role="alert">
          {error}
        </p>
      )}
    </form>
  );
}

export default function DeliveryRules() {
  const [config, setConfig] = useState(null);
  const [error, setError] = useState("");
  useEffect(() => {
    let alive = true;
    rpc("online_shop_config")
      .then((result) => {
        if (alive) setConfig(result);
      })
      .catch((e) => {
        if (alive) setError(e.message);
      });
    return () => {
      alive = false;
    };
  }, []);
  return (
    <details className="online-settings">
      <summary>Horários e áreas de entrega</summary>
      {error ? (
        <p className="online-error" role="alert">
          {error}
        </p>
      ) : config?.weekly_hours ? (
        <RulesForm config={config} />
      ) : config ? (
        <p>Configuração de horários indisponível neste ambiente.</p>
      ) : (
        <p role="status">Carregando configurações…</p>
      )}
    </details>
  );
}
