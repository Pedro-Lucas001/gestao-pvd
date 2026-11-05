import { useState, useEffect } from "react";
import { supabase, rpc } from "../lib/supabase";
import { cents, money } from "../lib/operations";
const categories = [
  "hamburgueres",
  "dogoes",
  "combos",
  "porcoes",
  "pasteis",
  "coxinhas",
  "bebidas",
  "adicionais",
];
export default function Catalog() {
  const [products, setProducts] = useState([]),
    [editing, setEditing] = useState(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  async function load() {
    const { data, error } = await supabase
      .from("products")
      .select("*")
      .order("name");
    if (error) setError("Não foi possível carregar o cardápio.");
    else setProducts(data);
  }
  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, []);
  return (
    <section className="management">
      <span className="eyebrow">CARDÁPIO</span>
      <h1>Sabores e preços da casa.</h1>
      <p>
        Alterações são persistidas e auditadas. Pedidos já enviados mantêm os
        preços originais.
      </p>
      <button className="primary" onClick={() => setEditing({})}>
        Adicionar produto
      </button>
      {editing && (
        <form
          className="management-panel form-columns"
          key={editing.id || "new"}
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            setError("");
            const f = new FormData(e.currentTarget);
            try {
              await rpc("save_product", {
                p_product: {
                  id: editing.id || null,
                  name: f.get("name"),
                  category: f.get("category"),
                  description: f.get("description"),
                  price_cents: cents(String(f.get("price"))),
                  sector: f.get("sector"),
                  active: f.get("active") === "on",
                  allowed_modifiers: String(f.get("modifiers"))
                    .split("\n")
                    .map((x) => x.trim())
                    .filter(Boolean),
                },
                p_reason: f.get("reason"),
              });
              setEditing(null);
              await load();
            } catch (e) {
              setError(e.message);
            } finally {
              setBusy(false);
            }
          }}
        >
          <label>
            Nome
            <input
              name="name"
              required
              minLength={2}
              maxLength={120}
              defaultValue={editing.name}
            />
          </label>
          <label>
            Preço (R$)
            <input
              name="price"
              required
              inputMode="decimal"
              defaultValue={
                editing.price_cents !== undefined
                  ? (editing.price_cents / 100).toFixed(2)
                  : ""
              }
            />
          </label>
          <label>
            Categoria
            <select
              name="category"
              defaultValue={editing.category || "hamburgueres"}
            >
              {categories.map((c) => (
                <option key={c}>{c}</option>
              ))}
            </select>
          </label>
          <label>
            Setor
            <select name="sector" defaultValue={editing.sector || "grill"}>
              <option value="grill">Chapa</option>
              <option value="fryer">Fritura</option>
              <option value="bar">Bebidas</option>
            </select>
          </label>
          <label className="span-all">
            Descrição
            <textarea
              name="description"
              maxLength={1000}
              defaultValue={editing.description}
            />
          </label>
          <label className="span-all">
            Modificadores permitidos · um por linha
            <textarea
              name="modifiers"
              defaultValue={editing.allowed_modifiers?.join("\n") || ""}
            />
          </label>
          <label>
            <input
              type="checkbox"
              name="active"
              defaultChecked={editing.active !== false}
            />{" "}
            Disponível para venda
          </label>
          <label>
            Justificativa
            <input name="reason" required minLength={5} maxLength={500} />
          </label>
          <button
            className="secondary"
            type="button"
            onClick={() => setEditing(null)}
          >
            Fechar edição
          </button>
          <button className="primary" disabled={busy}>
            Salvar produto
          </button>
        </form>
      )}
      {error && (
        <p role="alert" className="error-message">
          {error}
        </p>
      )}
      <div className="management-panel table-wrap">
        <table>
          <thead>
            <tr>
              <th>Produto</th>
              <th>Categoria</th>
              <th>Preço</th>
              <th>Disponível</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {products.map((p) => (
              <tr key={p.id}>
                <td>{p.name}</td>
                <td>{p.category}</td>
                <td>{money(p.price_cents)}</td>
                <td>{p.active ? "Sim" : "Não"}</td>
                <td>
                  <button className="text-button" onClick={() => setEditing(p)}>
                    Editar
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
