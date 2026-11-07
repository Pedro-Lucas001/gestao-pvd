import { useState, useEffect } from "react";
import { rpc, supabase } from "../lib/supabase";
import { rememberDevice, deviceToken } from "../auth/device";
export default function TerminalSetup() {
  const [devices, setDevices] = useState([]),
    [notice, setNotice] = useState(""),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  async function load() {
    const { data } = await supabase
      .from("terminals")
      .select("id,name,active,created_at")
      .order("created_at", { ascending: false });
    setDevices(data || []);
  }
  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, []);
  return (
    <>
      <article className="management-panel">
        <h2>Terminais da equipe</h2>
        <p>
          {deviceToken()
            ? "Este navegador possui um identificador de terminal."
            : "Este navegador ainda não foi cadastrado."}{" "}
          O identificador é mantido ao trocar de conta; PINs incorretos de
          diferentes operadores contam para o mesmo bloqueio de 3 minutos.
        </p>
        <form
          className="form-columns"
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            setError("");
            const f = new FormData(e.currentTarget);
            try {
              const result = await rpc("register_terminal", {
                p_name: f.get("name"),
                p_reason: f.get("reason"),
              });
              rememberDevice(result.token);
              setNotice(
                "Terminal cadastrado neste navegador. Guarde o acesso físico a este dispositivo.",
              );
              await load();
            } catch (e) {
              setError(e.message);
            } finally {
              setBusy(false);
            }
          }}
        >
          <label>
            Nome deste terminal
            <input
              name="name"
              required
              minLength={2}
              maxLength={100}
              placeholder="Balcão 01"
            />
          </label>
          <label>
            Justificativa
            <input name="reason" required minLength={5} maxLength={500} />
          </label>
          <button className="primary" disabled={busy}>
            Cadastrar este navegador
          </button>
        </form>
        {devices.map((d) => (
          <div className="report-row" key={d.id}>
            <strong>{d.name}</strong>
            <span>{d.active ? "Ativo" : "Revogado"}</span>
            {d.active && (
              <button
                className="text-button"
                onClick={async () => {
                  const reason = prompt(
                    "Justificativa para revogar este terminal:",
                  );
                  if (!reason) return;
                  try {
                    await rpc("revoke_terminal", {
                      p_terminal: d.id,
                      p_reason: reason,
                    });
                    await load();
                  } catch (e) {
                    setError(e.message);
                  }
                }}
              >
                Revogar
              </button>
            )}
          </div>
        ))}
      </article>
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
      {notice && (
        <p className="success-message" role="status">
          {notice}
        </p>
      )}
    </>
  );
}
