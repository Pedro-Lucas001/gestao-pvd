import { useState, useEffect, useRef } from "react";
import { supabase, rpc } from "../lib/supabase";
import { command } from "./commands";
export default function Inventory() {
  const [ingredients, setIngredients] = useState([]),
    [products, setProducts] = useState([]),
    [recipe, setRecipe] = useState([]),
    [rules, setRules] = useState([]),
    [product, setProduct] = useState(""),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [editing, setEditing] = useState(null);
  const chooseVersion = useRef(0);
  const [recipeReady, setRecipeReady] = useState(false);
  async function load() {
    const [i, p] = await Promise.all([
      supabase.from("ingredients").select("*").order("name"),
      supabase
        .from("products")
        .select("id,name,allowed_modifiers")
        .order("name"),
    ]);
    if (i.error || p.error) setError("Não foi possível carregar os insumos.");
    else {
      setIngredients(i.data);
      setProducts(p.data);
    }
  }
  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, []);
  async function run(fn) {
    setBusy(true);
    setError("");
    try {
      await fn();
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  async function choose(id) {
    const version = ++chooseVersion.current;
    setProduct(id);
    setRecipeReady(false);
    setRecipe([]);
    setRules([]);
    if (!id) return;
    const [rulesResult, recipeResult] = await Promise.all([
      supabase
        .from("recipe_modifier_rules")
        .select("modifier,ingredient_id,quantity_delta")
        .eq("product_id", id),
      supabase
        .from("recipe_items")
        .select("ingredient_id,quantity")
        .eq("product_id", id),
    ]);
    if (version !== chooseVersion.current) return;
    if (rulesResult.error || recipeResult.error)
      setError(
        "Não foi possível carregar a ficha. Selecione o produto novamente.",
      );
    else {
      setRules(rulesResult.data || []);
      setRecipe(recipeResult.data || []);
      setRecipeReady(true);
      setError("");
    }
  }
  return (
    <section className="management">
      <span className="eyebrow">ESTOQUE E FICHAS</span>
      <h1>Cada insumo sob controle.</h1>
      <p>
        Cadastre quantidades e custos reais. As vendas baixam a receita padrão
        uma única vez; saldo negativo gera alerta e exige conferência.
      </p>
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
      <button className="primary" onClick={() => setEditing({})}>
        Novo insumo
      </button>
      {editing && (
        <form
          className="management-panel form-columns"
          key={editing.id || "new"}
          onSubmit={(e) => {
            e.preventDefault();
            const f = new FormData(e.currentTarget);
            run(async () => {
              await rpc("save_ingredient", {
                p_id: editing.id || null,
                p_name: f.get("name"),
                p_unit: f.get("unit"),
                p_minimum: Number(f.get("minimum")),
                p_cost: Number((Number(f.get("cost")) * 100).toFixed(4)),
                p_reason: f.get("reason"),
              });
              setEditing(null);
            });
          }}
        >
          <label>
            Insumo
            <input
              name="name"
              required
              minLength={2}
              maxLength={120}
              defaultValue={editing.name}
            />
          </label>
          <label>
            Unidade
            <select name="unit" defaultValue={editing.unit || "un"}>
              <option value="un">Unidade</option>
              <option value="g">Gramas</option>
              <option value="ml">Mililitros</option>
            </select>
          </label>
          <label>
            Estoque mínimo
            <input
              name="minimum"
              type="number"
              min="0"
              step="0.001"
              required
              defaultValue={editing.minimum_stock || 0}
            />
          </label>
          <label>
            Custo em R$ por unidade/g/ml
            <input
              name="cost"
              type="number"
              min="0"
              step="0.000001"
              required
              defaultValue={
                editing.id ? Number(editing.unit_cost_cents || 0) / 100 : ""
              }
            />
          </label>
          <label className="span-all">
            Justificativa
            <input name="reason" required minLength={5} maxLength={500} />
          </label>
          <button
            type="button"
            className="secondary"
            onClick={() => setEditing(null)}
          >
            Fechar edição
          </button>
          <button className="primary" disabled={busy}>
            Salvar insumo
          </button>
        </form>
      )}
      <article className="management-panel">
        <h2>Saldos atuais</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Insumo</th>
                <th>Saldo</th>
                <th>Mínimo</th>
                <th>Custo por unidade (R$)</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {ingredients.map((i) => (
                <tr
                  key={i.id}
                  className={
                    Number(i.stock) <= Number(i.minimum_stock)
                      ? "stock-alert"
                      : ""
                  }
                >
                  <td>{i.name}</td>
                  <td>
                    {i.stock} {i.unit}
                  </td>
                  <td>{i.minimum_stock}</td>
                  <td>
                    {(Number(i.unit_cost_cents) / 100).toLocaleString("pt-BR", {
                      style: "currency",
                      currency: "BRL",
                      maximumFractionDigits: 6,
                    })}
                  </td>
                  <td>
                    <button
                      className="text-button"
                      onClick={() => setEditing(i)}
                    >
                      Editar cadastro
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </article>
      <div className="management-grid">
        <form
          className="management-panel"
          onSubmit={(e) => {
            e.preventDefault();
            const f = new FormData(e.currentTarget);
            run(() =>
              command("adjust_stock", {
                p_id: f.get("ingredient"),
                p_delta: Number(f.get("delta")),
                p_reason: f.get("reason"),
              }),
            );
          }}
        >
          <h2>Entrada, perda ou correção</h2>
          <label>
            Insumo
            <select name="ingredient" required>
              {ingredients.map((i) => (
                <option key={i.id} value={i.id}>
                  {i.name} · {i.unit}
                </option>
              ))}
            </select>
          </label>
          <label>
            Quantidade · use negativo para saída
            <input name="delta" type="number" step="0.001" required />
          </label>
          <label>
            Justificativa
            <input name="reason" required minLength={5} maxLength={500} />
          </label>
          <button className="primary" disabled={busy || !ingredients.length}>
            Registrar movimento
          </button>
        </form>
        <form
          className="management-panel"
          onSubmit={(e) => {
            e.preventDefault();
            const f = new FormData(e.currentTarget);
            run(() =>
              rpc("save_recipe", {
                p_product: product,
                p_items: recipe.map((i) => ({
                  ingredient_id: i.ingredient_id,
                  quantity: Number(i.quantity),
                })),
                p_rules: rules.map((r) => ({
                  ...r,
                  quantity_delta: Number(r.quantity_delta),
                })),
                p_reason: f.get("reason"),
              }),
            );
          }}
        >
          <h2>Ficha técnica</h2>
          <label>
            Produto
            <select
              required
              value={product}
              onChange={(e) => choose(e.target.value)}
            >
              <option value="">Selecione o produto</option>
              {products.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
          {recipe.map((r, index) => (
            <div className="recipe-row" key={index}>
              <select
                aria-label={`Insumo ${index + 1}`}
                required
                value={r.ingredient_id}
                onChange={(e) =>
                  setRecipe(
                    recipe.map((x, i) =>
                      i === index ? { ...x, ingredient_id: e.target.value } : x,
                    ),
                  )
                }
              >
                <option value="">Insumo</option>
                {ingredients.map((i) => (
                  <option key={i.id} value={i.id}>
                    {i.name} · {i.unit}
                  </option>
                ))}
              </select>
              <input
                aria-label={`Quantidade ${index + 1}`}
                type="number"
                step="0.001"
                min="0.001"
                required
                value={r.quantity}
                onChange={(e) =>
                  setRecipe(
                    recipe.map((x, i) =>
                      i === index ? { ...x, quantity: e.target.value } : x,
                    ),
                  )
                }
              />
              <button
                className="icon-button"
                type="button"
                aria-label={`Remover insumo ${index + 1}`}
                onClick={() => setRecipe(recipe.filter((_, i) => i !== index))}
              >
                ×
              </button>
            </div>
          ))}
          <button
            className="text-button"
            type="button"
            onClick={() =>
              setRecipe([...recipe, { ingredient_id: "", quantity: 1 }])
            }
          >
            ＋ Adicionar insumo
          </button>
          <h3>Regras por modificador</h3>
          <p>
            Use quantidade negativa para excluir um insumo, positiva para
            adicionar. Configure as quantidades reais; o consumo final nunca
            fica negativo.
          </p>
          {rules.map((r, index) => (
            <div className="modifier-rule" key={index}>
              <select
                aria-label={`Modificador ${index + 1}`}
                required
                value={r.modifier}
                onChange={(e) =>
                  setRules(
                    rules.map((x, i) =>
                      i === index ? { ...x, modifier: e.target.value } : x,
                    ),
                  )
                }
              >
                <option value="">Modificador</option>
                {(
                  products.find((p) => p.id === product)?.allowed_modifiers ||
                  []
                ).map((m) => (
                  <option key={m}>{m}</option>
                ))}
              </select>
              <select
                aria-label={`Insumo do modificador ${index + 1}`}
                required
                value={r.ingredient_id}
                onChange={(e) =>
                  setRules(
                    rules.map((x, i) =>
                      i === index ? { ...x, ingredient_id: e.target.value } : x,
                    ),
                  )
                }
              >
                <option value="">Insumo</option>
                {ingredients.map((i) => (
                  <option key={i.id} value={i.id}>
                    {i.name} · {i.unit}
                  </option>
                ))}
              </select>
              <input
                aria-label={`Variação de quantidade ${index + 1}`}
                type="number"
                step="0.001"
                required
                value={r.quantity_delta}
                onChange={(e) =>
                  setRules(
                    rules.map((x, i) =>
                      i === index
                        ? { ...x, quantity_delta: e.target.value }
                        : x,
                    ),
                  )
                }
              />
              <button
                type="button"
                className="icon-button"
                aria-label={`Remover regra ${index + 1}`}
                onClick={() => setRules(rules.filter((_, i) => i !== index))}
              >
                ×
              </button>
            </div>
          ))}
          <button
            type="button"
            className="text-button"
            onClick={() =>
              setRules([
                ...rules,
                { modifier: "", ingredient_id: "", quantity_delta: -1 },
              ])
            }
          >
            ＋ Adicionar regra de modificador
          </button>
          <label>
            Justificativa
            <input name="reason" required minLength={5} maxLength={500} />
          </label>
          <button
            className="primary"
            disabled={!product || !recipeReady || busy}
          >
            Salvar receita
          </button>
          <p>
            Receita vazia desativa a baixa automática desse produto. Alterações
            não reescrevem as vendas passadas.
          </p>
        </form>
      </div>
    </section>
  );
}
