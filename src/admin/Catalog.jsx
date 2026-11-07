import { useState, useEffect } from "react";
import { supabase, rpc } from "../lib/supabase";
import { supabaseUrl } from "../lib/supabaseConfig";
import { cents, money } from "../lib/operations";
import { categories } from "../data/categories";
import { operationKey } from "../public/cart";
import {
  PRODUCT_IMAGE_BUCKET,
  PRODUCT_IMAGE_PREFIX,
  prepareProductImage,
  productImageUrl,
} from "../lib/productImages";
import "./AdminControl.css";
function Photo({ path, name }) {
  return (
    <img
      className="catalog-photo"
      src={productImageUrl(path, supabaseUrl) || "/menu/hamburgueres.svg"}
      alt={`Foto de ${name}`}
    />
  );
}
export function ProductEditor({ product, onSave, onCancel, busy, error }) {
  const [image, setImage] = useState(product.image_path || ""),
    [uploading, setUploading] = useState(false),
    [photoError, setPhotoError] = useState("");
  async function upload(file) {
    if (!file) return;
    setUploading(true);
    setPhotoError("");
    try {
      const blob = await prepareProductImage(file),
        path = `${operationKey()}.webp`;
      const { error } = await supabase.storage
        .from(PRODUCT_IMAGE_BUCKET)
        .upload(path, blob, {
          contentType: "image/webp",
          cacheControl: "31536000",
          upsert: false,
        });
      if (error)
        throw new Error(
          "Não foi possível enviar a foto. Confira a conexão, seu acesso de administrador e a ativação do armazenamento.",
        );
      setImage(`${PRODUCT_IMAGE_PREFIX}${path}`);
    } catch (e) {
      setPhotoError(e.message);
    } finally {
      setUploading(false);
    }
  }
  return (
    <form
      className="management-panel form-columns"
      onSubmit={(e) => {
        e.preventDefault();
        const f = new FormData(e.currentTarget);
        try {
          onSave(
            {
              id: product.id,
              name: f.get("name"),
              category: f.get("category"),
              description: f.get("description"),
              price_cents: cents(String(f.get("price"))),
              sector: f.get("sector"),
              image_path: image || null,
              active: f.get("active") === "on",
              allowed_modifiers: String(f.get("modifiers") || "")
                .split("\n")
                .map((s) => s.trim())
                .filter(Boolean),
            },
            f.get("reason"),
          );
        } catch (e) {
          setPhotoError(e.message);
        }
      }}
    >
      <h2 className="span-all">
        {product.isNew ? "Novo produto no cardápio" : `Editar ${product.name}`}
      </h2>
      <fieldset disabled={busy || uploading} className="form-columns span-all">
        <label>
          Nome
          <input
            name="name"
            required
            minLength={2}
            maxLength={120}
            defaultValue={product.name}
          />
        </label>
        <label>
          Preço (R$)
          <input
            name="price"
            required
            inputMode="decimal"
            defaultValue={
              product.price_cents !== undefined
                ? (product.price_cents / 100).toFixed(2)
                : ""
            }
          />
        </label>
        <label>
          Categoria
          <select
            name="category"
            defaultValue={product.category || "hamburgueres"}
          >
            {categories
              .filter(([id]) => id !== "all")
              .map(([id, label]) => (
                <option key={id} value={id}>
                  {label}
                </option>
              ))}
          </select>
        </label>
        <label>
          Setor de preparo
          <select name="sector" defaultValue={product.sector || "grill"}>
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
            defaultValue={product.description}
          />
        </label>
        <div className="catalog-photo-editor span-all">
          <Photo path={image} name={product.name || "novo produto"} />
          <div>
            <strong>Foto do produto</strong>
            <p>
              JPG, PNG ou WebP de até 5 MB. A foto será preparada para o
              cardápio e exibida no cardápio quando o produto for salvo.
            </p>
            <label>
              Selecionar nova foto
              <input
                type="file"
                accept="image/jpeg,image/png,image/webp"
                onChange={(e) => upload(e.target.files[0])}
              />
            </label>
            <button
              className="text-button"
              type="button"
              onClick={() => setImage("")}
            >
              Usar imagem padrão da categoria
            </button>
            {uploading && <p role="status">Preparando e enviando foto…</p>}
          </div>
        </div>
        <label className="span-all">
          Personalizações permitidas · uma por linha
          <textarea
            name="modifiers"
            maxLength={1700}
            defaultValue={product.allowed_modifiers?.join("\n") || ""}
          />
        </label>
        <label className="checkbox">
          <input
            type="checkbox"
            name="active"
            defaultChecked={product.active !== false}
          />
          Disponível no cardápio e para venda
        </label>
        <label>
          Justificativa
          <input name="reason" required minLength={5} maxLength={500} />
        </label>
      </fieldset>
      {(photoError || error) && (
        <p className="error-message span-all" role="alert">
          {photoError || error}
        </p>
      )}
      <button
        type="button"
        className="secondary"
        disabled={busy || uploading}
        onClick={onCancel}
      >
        Cancelar edição
      </button>
      <button className="primary" disabled={busy || uploading}>
        {busy ? "Salvando…" : "Salvar produto e imagem"}
      </button>
    </form>
  );
}
export default function Catalog() {
  const [products, setProducts] = useState([]),
    [editing, setEditing] = useState(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [search, setSearch] = useState(""),
    [success, setSuccess] = useState("");
  async function load() {
    const { data, error } = await supabase
      .from("products")
      .select("*")
      .order("name");
    if (error) setError("Não foi possível carregar os produtos.");
    else setProducts(data);
  }
  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, []);
  async function save(product, reason) {
    setBusy(true);
    setError("");
    setSuccess("");
    try {
      await rpc("save_product", { p_product: product, p_reason: reason });
      setEditing(null);
      setSuccess(
        "Produto salvo. As próximas consultas ao cardápio e ao caixa receberão a atualização.",
      );
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  const visible = products.filter((p) =>
    `${p.name} ${p.category}`
      .toLocaleLowerCase("pt-BR")
      .includes(search.toLocaleLowerCase("pt-BR")),
  );
  return (
    <section className="management">
      <span className="eyebrow">CARDÁPIO E IMAGENS</span>
      <h1>Seus produtos, do seu jeito.</h1>
      <p>
        Cadastre produtos, altere fotos, preços, descrições e disponibilidade.
        Depois, configure a ficha técnica em Estoque e fichas para controlar
        consumo e custos.
      </p>
      <div className="catalog-toolbar">
        <button
          className="primary"
          disabled={busy}
          onClick={() => {
            setEditing({ id: operationKey(), isNew: true });
            setError("");
            setSuccess("");
          }}
        >
          Adicionar produto
        </button>
        <label>
          Buscar produto
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Nome ou categoria"
          />
        </label>
      </div>
      {success && (
        <p role="status" className="control-success">
          {success}
        </p>
      )}
      {editing && (
        <ProductEditor
          key={editing.id}
          product={editing}
          onSave={save}
          onCancel={() => {
            setEditing(null);
            setError("");
          }}
          busy={busy}
          error={error}
        />
      )}
      {error && !editing && (
        <p role="alert" className="error-message">
          {error}
        </p>
      )}
      <div className="management-panel table-wrap">
        <table>
          <thead>
            <tr>
              <th>Foto</th>
              <th>Produto</th>
              <th>Categoria</th>
              <th>Preço</th>
              <th>Disponível</th>
              <th>Ações</th>
            </tr>
          </thead>
          <tbody>
            {visible.map((p) => (
              <tr key={p.id}>
                <td>
                  <Photo path={p.image_path} name={p.name} />
                </td>
                <td>{p.name}</td>
                <td>
                  {categories.find(([id]) => id === p.category)?.[1] ||
                    p.category}
                </td>
                <td>{money(p.price_cents)}</td>
                <td>{p.active ? "Sim" : "Não"}</td>
                <td>
                  <button
                    className="text-button"
                    disabled={busy}
                    onClick={() => {
                      setEditing(p);
                      setError("");
                      setSuccess("");
                    }}
                  >
                    Editar {p.name}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!visible.length && <p>Nenhum produto para esta busca.</p>}
      </div>
    </section>
  );
}
