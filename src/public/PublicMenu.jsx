import { productImageUrl } from "../lib/productImages";
import { supabaseUrl } from "../lib/supabaseConfig";
import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  ArrowDown,
  ShoppingBag,
  Plus,
  ArrowRight,
  Flame,
  LockKeyhole,
  Search,
  Utensils,
  X,
} from "lucide-react";
import sourceMenu from "../data/menu.json";
import { categories } from "../data/categories";
import { money } from "../lib/operations";
import { configured, loadPublicMenu } from "./menuApi";
import { filterMenu, publicProducts } from "./menuData";
import "./PublicMenu.css";
import "./CustomerOrder.css";
import { useCart } from "./cart";
import { customerApi } from "./customerApi";
import CustomerChat from "./CustomerChat";

const referenceMenu = publicProducts(
  sourceMenu.map((p) => ({
    ...p,
    price_cents: p.price,
    image_path: `/menu/${p.category === "combos" ? "hamburgueres" : p.category}.svg`,
  })),
);

function MenuItem({ product, onAdd }) {
  const [failed, setFailed] = useState(false);
  return (
    <article className="menu-item" data-menu-product>
      <div className="menu-item-image">
        {product.image_path && !failed ? (
          <img
            src={productImageUrl(product.image_path, supabaseUrl)}
            alt=""
            loading="lazy"
            onError={() => setFailed(true)}
          />
        ) : (
          <Utensils aria-hidden="true" size={32} />
        )}
      </div>
      <div className="menu-item-copy">
        <span className="menu-category-label">
          {categories.find(([id]) => id === product.category)?.[1] ||
            product.category}
        </span>
        <h3>{product.name}</h3>
        <p>
          {product.description || "Consulte os ingredientes com nossa equipe."}
        </p>
        <strong className="menu-price">{money(product.price_cents)}</strong>
        <button
          type="button"
          className="menu-add"
          onClick={() => onAdd(product)}
          aria-label={`Adicionar ${product.name}`}
        >
          <Plus size={16} />
          Adicionar
        </button>
      </div>
    </article>
  );
}

export default function PublicMenu() {
  const { items, add } = useCart();
  const [shop, setShop] = useState(null);
  useEffect(() => {
    const c = new AbortController();
    customerApi("config", {}, c.signal)
      .then(setShop)
      .catch(() => {});
    return () => c.abort();
  }, []);
  const [products, setProducts] = useState(configured ? [] : referenceMenu);
  const [loading, setLoading] = useState(configured);
  const [error, setError] = useState("");
  const [category, setCategory] = useState("all");
  const [query, setQuery] = useState("");
  useEffect(() => {
    document.title = "Planeta Lanches · Cardápio";
  }, []);
  const load = useCallback(async (signal) => {
    if (!configured) return;
    try {
      const data = await loadPublicMenu(signal);
      if (signal.aborted) return;
      setProducts(data);
      setError("");
    } catch {
      if (!signal.aborted)
        setError(
          "Não foi possível atualizar o cardápio. Tente novamente ou consulte nossa equipe.",
        );
    } finally {
      if (!signal.aborted) setLoading(false);
    }
  }, []);
  useEffect(() => {
    const controller = new AbortController();
    const timer = setTimeout(() => load(controller.signal), 0);
    const interval = setInterval(() => load(controller.signal), 60000);
    const refresh = () => {
      if (document.visibilityState === "visible") load(controller.signal);
    };
    window.addEventListener("online", refresh);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      controller.abort();
      clearTimeout(timer);
      clearInterval(interval);
      window.removeEventListener("online", refresh);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, [load]);
  const filtered = filterMenu(products, category, query);
  const availableCategories = [
    ...categories.filter(
      ([id]) => id === "all" || products.some((p) => p.category === id),
    ),
    ...[...new Set(products.map((p) => p.category))]
      .filter((id) => !categories.some(([known]) => id === known))
      .map((id) => [id, id]),
  ];

  return (
    <div className="menu-page">
      <a className="menu-skip" href="#menu-produtos">
        Ir para o cardápio
      </a>
      <header className="menu-header">
        <Link
          to="/"
          className="menu-wordmark"
          aria-label="Planeta Lanches · início"
        >
          <span className="menu-brand-icon">
            <Flame size={24} aria-hidden="true" />
          </span>
          <span>
            PLANETA <b>LANCHES</b>
            <small>Sabor que te leva mais longe.</small>
          </span>
        </Link>
        <Link to="/login" className="menu-staff-link">
          <LockKeyhole size={16} />
          Área da equipe
          <ArrowRight size={15} />
        </Link>
      </header>
      <main>
        <section className="menu-hero" aria-labelledby="menu-title">
          <div className="menu-hero-copy">
            <span className="menu-eyebrow">
              <span />
              BEM-VINDO AO PLANETA
            </span>
            <h1 id="menu-title">
              Seu próximo
              <br />
              <em>favorito.</em>
            </h1>
            <p>
              Da chapa ao primeiro pedaço, sabor em cada detalhe. Explore o
              cardápio e escolha o que combina com a sua fome.
            </p>
            <a className="menu-explore" href="#menu-produtos">
              Explorar cardápio
              <ArrowDown size={18} />
            </a>
            <div className="menu-hero-note">
              <Utensils size={17} />
              Escolha, personalize e acompanhe seu pedido por aqui.
            </div>
          </div>
          <div className="menu-hero-art">
            <img
              src="/brand/planeta-art.png"
              alt="Planeta Lanches: hambúrguer, coxinha e batatas"
              fetchPriority="high"
            />
          </div>
        </section>
        <section
          className="menu-catalog"
          id="menu-produtos"
          aria-labelledby="menu-catalog-title"
        >
          <div className="menu-catalog-heading">
            <div>
              <span className="menu-section-kicker">ESCOLHA O SEU SABOR</span>
              <h2 id="menu-catalog-title">
                Nosso cardápio<span>.</span>
              </h2>
            </div>
            <div className="menu-search">
              <Search size={19} aria-hidden="true" />
              <label className="sr-only" htmlFor="public-menu-search">
                Buscar no cardápio
              </label>
              <input
                id="public-menu-search"
                type="search"
                placeholder="O que você procura?"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
              {query && (
                <button
                  type="button"
                  aria-label="Limpar busca"
                  onClick={() => setQuery("")}
                >
                  <X size={18} />
                </button>
              )}
            </div>
          </div>
          <div
            className="menu-categories"
            role="group"
            aria-label="Categorias do cardápio"
          >
            {availableCategories.map(([id, label]) => (
              <button
                type="button"
                key={id}
                aria-pressed={category === id}
                onClick={() => setCategory(id)}
              >
                {label}
              </button>
            ))}
          </div>
          {!configured && (
            <p className="menu-reference" role="note">
              Cardápio de referência. Confirme preços e disponibilidade com
              nossa equipe.
            </p>
          )}
          {error && (
            <div className="menu-error" role="alert">
              <p>{error}</p>
              <button
                type="button"
                onClick={() => load(new AbortController().signal)}
              >
                Tentar novamente
              </button>
            </div>
          )}
          {loading ? (
            <div className="menu-empty" role="status">
              Preparando o cardápio…
            </div>
          ) : (
            <>
              <p className="menu-results" role="status">
                {filtered.length} {filtered.length === 1 ? "opção" : "opções"}
                {query && ` para “${query}”`}
              </p>
              {availableCategories
                .filter(
                  ([id]) =>
                    id !== "all" && filtered.some((p) => p.category === id),
                )
                .map(([id, label]) => (
                  <section
                    className="menu-category-section"
                    key={id}
                    aria-labelledby={`category-${id}`}
                  >
                    <div className="menu-section-heading">
                      <h3 id={`category-${id}`}>{label}</h3>
                      <span>
                        {filtered.filter((p) => p.category === id).length}{" "}
                        opções
                      </span>
                    </div>
                    <div className="menu-products">
                      {filtered
                        .filter((p) => p.category === id)
                        .map((p) => (
                          <MenuItem key={p.id} product={p} onAdd={add} />
                        ))}
                    </div>
                  </section>
                ))}
              {!filtered.length && !error && (
                <div className="menu-empty">
                  <Utensils size={30} />
                  <h3>
                    {products.length
                      ? "Ainda não encontrou seu favorito?"
                      : "O cardápio está sendo preparado."}
                  </h3>
                  <p>
                    {products.length
                      ? "Tente outra busca ou explore as categorias."
                      : "Consulte nossa equipe para conhecer as opções disponíveis."}
                  </p>
                  {products.length > 0 && (
                    <button
                      type="button"
                      onClick={() => {
                        setQuery("");
                        setCategory("all");
                      }}
                    >
                      Ver todas as opções
                    </button>
                  )}
                </div>
              )}
            </>
          )}
          <div className="menu-service-note">
            <Flame size={22} aria-hidden="true" />
            <p>
              <strong>Do seu jeito, com nosso capricho.</strong>
              <br />
              Dúvidas sobre ingredientes ou personalização? Converse com nossa
              equipe antes de pedir.
            </p>
          </div>
        </section>
      </main>
      <footer className="menu-footer">
        <span>
          PLANETA LANCHES<small>Carpina · Pernambuco</small>
        </span>
        <p>Escolha seu favorito. A gente cuida do sabor.</p>
        <Link to="/login">
          Acesso de funcionários e administração
          <ArrowRight size={14} />
        </Link>
      </footer>
      {items.length > 0 && (
        <div className="customer-cart-bar">
          <span>
            <ShoppingBag size={20} />
            <strong>{items.reduce((n, i) => n + i.quantity, 0)} itens</strong>
            <small>
              Subtotal estimado{" "}
              {money(items.reduce((n, i) => n + i.price_cents * i.quantity, 0))}
            </small>
          </span>
          <Link to="/pedido">
            Revisar meu pedido
            <ArrowRight size={18} />
          </Link>
        </div>
      )}
      <CustomerChat shop={shop} catalog={shop?.catalog || products} />
    </div>
  );
}
