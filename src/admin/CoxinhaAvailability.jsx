import { useEffect, useState } from "react";
import { rpc } from "../lib/supabase";

export default function CoxinhaAvailability() {
  const [rows, setRows] = useState(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [saved, setSaved] = useState("");
  useEffect(() => {
    let alive = true;
    rpc("online_shop_config")
      .then((config) => {
        if (!alive) return;
        const available = config.coxinha_flavors || ["Frango", "Presunto"];
        setRows(
          [...new Set(["Frango", "Presunto", ...available])].map((name) => ({
            name,
            available: available.includes(name),
          })),
        );
      })
      .catch((e) => {
        if (alive) setError(e.message);
      });
    return () => {
      alive = false;
    };
  }, []);
  function patch(index, update) {
    setRows((all) =>
      all.map((row, i) => (i === index ? { ...row, ...update } : row)),
    );
    setSaved("");
  }
  async function save(e) {
    e.preventDefault();
    setBusy(true);
    setError("");
    setSaved("");
    try {
      await rpc("online_set_coxinha_flavors", {
        p_flavors: rows
          .filter((row) => row.available)
          .map((row) => row.name.trim()),
        p_reason: new FormData(e.currentTarget).get("reason"),
      });
      setSaved(
        "Disponibilidade atualizada para todas as porções de mini coxinhas. Novos pedidos usam esses sabores.",
      );
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="management-panel coxinha-availability">
      <h2>Mini coxinhas: sabores disponíveis hoje</h2>
      <p>
        Marque os sabores disponíveis. Mistas / misturadas é oferecida
        automaticamente quando houver pelo menos dois sabores. Pedidos já feitos
        mantêm a escolha registrada.
      </p>
      {rows && (
        <form onSubmit={save}>
          <fieldset disabled={busy}>
            {rows.map((row, index) => (
              <div className="coxinha-flavor-row" key={index}>
                <label className="checkbox">
                  <input
                    type="checkbox"
                    checked={row.available}
                    onChange={(e) =>
                      patch(index, { available: e.target.checked })
                    }
                  />
                  Disponível
                </label>
                <label>
                  Sabor {index + 1}
                  <input
                    value={row.name}
                    required={row.available}
                    minLength={2}
                    maxLength={50}
                    onChange={(e) => patch(index, { name: e.target.value })}
                  />
                </label>
                <button
                  type="button"
                  className="text-button"
                  onClick={() =>
                    setRows((all) => all.filter((_, i) => i !== index))
                  }
                >
                  Remover sabor {index + 1}
                </button>
              </div>
            ))}
            {rows.length < 6 && (
              <button
                type="button"
                className="secondary"
                onClick={() =>
                  setRows((all) => [...all, { name: "", available: true }])
                }
              >
                Adicionar sabor
              </button>
            )}
            {rows.filter((row) => row.available).length === 0 && (
              <p role="status">
                Sem sabores disponíveis, todas as porções de mini coxinhas ficam
                ocultas no cardápio.
              </p>
            )}
            <label>
              Justificativa da disponibilidade
              <input name="reason" required minLength={5} maxLength={500} />
            </label>
            <button className="primary" disabled={busy}>
              {busy ? "Salvando sabores…" : "Salvar sabores do dia"}
            </button>
          </fieldset>
        </form>
      )}
      {saved && (
        <p role="status" className="control-success">
          {saved}
        </p>
      )}
      {error && (
        <p role="alert" className="error-message">
          {error}
        </p>
      )}
    </section>
  );
}
