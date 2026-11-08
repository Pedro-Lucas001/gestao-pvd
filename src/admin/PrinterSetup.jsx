import { useEffect, useState } from "react";
import { rpc } from "../lib/supabase";

const labels = {
  pending: "Na fila",
  spooling: "Enviando à impressora",
  submitted: "Enviado ao Windows",
  uncertain: "Conferir impressora",
  cancelled: "Substituído/cancelado",
};
export default function PrinterSetup() {
  const [monitor, setMonitor] = useState(null),
    [credential, setCredential] = useState(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [version, setVersion] = useState(0);
  useEffect(() => {
    let alive = true;
    const load = () =>
      rpc("online_print_monitor")
        .then((data) => {
          if (alive) setMonitor(data);
        })
        .catch((e) => {
          if (alive) setError(e.message);
        });
    const first = setTimeout(load, 0),
      timer = setInterval(load, 10000);
    return () => {
      alive = false;
      clearTimeout(first);
      clearInterval(timer);
    };
  }, [version]);
  async function action(name, args) {
    setBusy(true);
    setError("");
    try {
      const result = await rpc(name, args);
      if (name === "online_register_printer") setCredential(result);
      setVersion((n) => n + 1);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <details className="online-settings">
      <summary>Impressão automática dos pedidos</summary>
      <p>
        Instale o agente no computador Windows da loja com a impressora
        configurada. O computador precisa ficar ligado. “Enviado ao Windows”
        confirma a entrega ao sistema de impressão; confira papel, conexão e
        impressão física.
      </p>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          const f = new FormData(e.currentTarget);
          action("online_register_printer", {
            p_name: f.get("name"),
            p_reason: f.get("reason"),
          });
        }}
      >
        <label>
          Nome do computador/impressora
          <input
            name="name"
            required
            minLength={2}
            maxLength={80}
            placeholder="Impressora da loja"
          />
        </label>
        <label>
          Justificativa
          <input name="reason" required minLength={5} maxLength={500} />
        </label>
        <p>
          Gerar uma credencial desativa o agente anterior. Ela permite somente
          retirar e confirmar cupons; guarde-a no computador da loja.
        </p>
        <button className="primary" disabled={busy}>
          Gerar credencial do agente
        </button>
      </form>
      {credential && (
        <div className="online-notice">
          <label>
            Credencial exibida apenas agora
            <input
              readOnly
              value={credential.token}
              onFocus={(e) => e.target.select()}
              autoComplete="off"
            />
          </label>
          <button className="secondary" onClick={() => setCredential(null)}>
            Já salvei; ocultar
          </button>
        </div>
      )}
      {monitor?.bridges.map((b) => (
        <p key={b.id}>
          {b.name} · {b.active ? "Ativo" : "Revogado"} · Última conexão:{" "}
          {b.last_seen_at
            ? new Date(b.last_seen_at).toLocaleString("pt-BR")
            : "Ainda não conectou"}{" "}
          {b.active && (
            <button
              className="secondary"
              disabled={busy}
              onClick={() =>
                action("online_revoke_printer", {
                  p_id: b.id,
                  p_reason: "Administrador revogou o agente de impressão",
                })
              }
            >
              Revogar
            </button>
          )}
        </p>
      ))}
      <p>
        Se houver falha ou falta de confirmação, o cupom fica para conferência.
        Reimprimir pode gerar uma segunda via; faça isso somente depois de
        verificar a impressora.
      </p>
      {monitor?.jobs.map((j) => (
        <div key={j.id} className="online-print-job">
          <span>
            #{j.number} · revisão {j.revision} · {labels[j.status]}
          </span>
          {["submitted", "uncertain"].includes(j.status) && (
            <form
              onSubmit={(e) => {
                e.preventDefault();
                action("online_retry_print", {
                  p_id: j.id,
                  p_reason: new FormData(e.currentTarget).get("reason"),
                });
              }}
            >
              <input
                aria-label={`Motivo da reimpressão do pedido ${j.number}`}
                name="reason"
                required
                minLength={5}
                maxLength={500}
                placeholder="Por que precisa de outra via?"
              />
              <label className="online-check">
                <input type="checkbox" required />
                Conferi a impressora e preciso reimprimir.
              </label>
              <button className="secondary" disabled={busy}>
                Solicitar segunda via
              </button>
            </form>
          )}
        </div>
      ))}
      {error && (
        <p role="alert" className="online-error">
          {error}
        </p>
      )}
    </details>
  );
}
