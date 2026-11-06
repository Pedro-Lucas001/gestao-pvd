import { useState, useEffect } from "react";
import { QRCodeSVG } from "qrcode.react";
import { supabase, rpc } from "../lib/supabase";
export default function OrderLinks() {
  const [links, setLinks] = useState([]),
    [url, setUrl] = useState(""),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  async function load() {
    const { data, error } = await supabase
      .from("order_links")
      .select("id,label,channel,active,expires_at")
      .order("created_at", { ascending: false });
    if (error) setError("Não foi possível consultar os links.");
    else setLinks(data);
  }
  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, []);
  return (
    <section className="management">
      <span className="eyebrow">MESAS E DELIVERY</span>
      <h1>O cliente faz o pedido.</h1>
      <p>
        Gere links/QRs do cardápio digital. O pagamento continua obrigatório
        antes da cozinha. No Pix de conta física, o administrador confere o
        crédito.
      </p>
      <form
        className="management-panel form-columns"
        onSubmit={async (e) => {
          e.preventDefault();
          setError("");
          setBusy(true);
          const f = new FormData(e.currentTarget);
          try {
            const result = await rpc("create_order_link", {
              p_label: f.get("label"),
              p_channel: f.get("channel"),
              p_days: Number(f.get("days")),
              p_reason: f.get("reason"),
            });
            setUrl(
              `${location.origin}/pedido?token=${encodeURIComponent(result.token)}`,
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
          Identificação
          <input
            name="label"
            required
            minLength={2}
            maxLength={80}
            placeholder="Mesa 01 ou Delivery"
          />
        </label>
        <label>
          Canal
          <select name="channel">
            <option value="table">Mesa</option>
            <option value="delivery">Delivery</option>
          </select>
        </label>
        <label>
          Validade em dias
          <input
            name="days"
            type="number"
            min="1"
            max="90"
            required
            defaultValue="30"
          />
        </label>
        <label>
          Justificativa
          <input name="reason" required minLength={5} maxLength={500} />
        </label>
        <button className="primary" disabled={busy}>
          Criar link e QR
        </button>
      </form>
      {url && (
        <div className="management-panel generated-link">
          <QRCodeSVG value={url} size={190} />
          <p>
            O link completo aparece somente agora. Guarde o QR antes de fechar
            esta tela. Para clientes, use o domínio HTTPS publicado da loja.
          </p>
          <input readOnly aria-label="Link de autoatendimento" value={url} />
          <button
            className="secondary"
            onClick={() => navigator.clipboard.writeText(url)}
          >
            Copiar link
          </button>
        </div>
      )}
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
      <article className="management-panel">
        <h2>Links cadastrados</h2>
        {links.map((l) => (
          <div className="report-row" key={l.id}>
            <strong>{l.label}</strong>
            <span>
              {l.channel} · {l.active ? "Ativo" : "Revogado"} · até{" "}
              {new Date(l.expires_at).toLocaleDateString("pt-BR")}
            </span>
            {l.active && (
              <button
                className="text-button"
                onClick={async () => {
                  const reason = prompt("Justificativa para revogar o link:");
                  if (!reason) return;
                  try {
                    await rpc("revoke_order_link", {
                      p_link: l.id,
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
    </section>
  );
}
