import { useState } from "react";
import {
  Check,
  ChevronDown,
  ChevronUp,
  Hamburger,
  Minus,
  Plus,
  Search,
  ShoppingCart,
  Trash2,
  X,
} from "lucide-react";
import { money, toggleModifier } from "../lib/operations";
import { operationUI as ui } from "../design/operational";
import OperationalBrand from "../design/OperationalBrand";
function ProductImage({ product }) {
  const [failed, setFailed] = useState(false);
  return (
    <div className="pl:mb-4 pl:flex pl:h-24 pl:w-24 pl:shrink-0 pl:items-center pl:justify-center pl:overflow-hidden pl:rounded-full pl:bg-[#1a1a1a] pl:transition-transform pl:group-hover:scale-105">
      {product.image_path && !failed
        ? (
          <img
            className="pl:h-full pl:w-full pl:object-contain"
            src={product.image_path}
            alt=""
            loading="lazy"
            onError={() => setFailed(true)}
          />
        )
        : (
          <Hamburger
            size={44}
            className="pl:text-[#ff5722]"
            aria-hidden="true"
          />
        )}
    </div>
  );
}
export default function PdvTemplate({
  products,
  filtered,
  categories,
  category,
  onCategory,
  query,
  onQuery,
  draft,
  total,
  frozen,
  selected,
  onSelect,
  onAdd,
  onUpdate,
  onCustomer,
  onChannel,
  paymentActions,
  operations,
  notices,
  demand,
}) {
  const subtotal = draft.order?.subtotal_cents ??
    draft.items.reduce(
      (sum, item) => sum + item.quantity * item.price_cents,
      0,
    );
  const units = draft.items.reduce((sum, item) => sum + item.quantity, 0);
  return (
    <div className="pl-pdv pl:flex pl:min-w-0 pl:flex-col pl:overflow-hidden pl:rounded-xl pl:border pl:border-gray-800 pl:bg-[#1a1a1a] pl:font-sans pl:text-gray-100 pl:lg:h-[calc(100dvh-9.5rem)] pl:lg:min-h-[42rem] pl:lg:flex-row">
      <section
        className="pl:@container/catalog pl:flex pl:min-w-0 pl:flex-1 pl:flex-col pl:p-4 pl:sm:p-6"
        id="catalogo"
        aria-label="Catálogo do PDV"
      >
        <header className="pl:mb-6 pl:flex pl:flex-wrap pl:items-center pl:justify-between pl:gap-5">
          <OperationalBrand title="Frente de caixa" />
          <label className="pl:relative pl:block pl:w-full pl:sm:w-1/2 pl:lg:w-1/3 pl:lg:min-w-[16.5rem]">
            <Search
              className="pl:pointer-events-none pl:absolute pl:top-4 pl:left-3 pl:h-5 pl:w-5 pl:text-gray-400"
              aria-hidden="true"
            />
            <input
              type="search"
              aria-label="Buscar produto"
              placeholder="Buscar item pelo nome..."
              value={query}
              onChange={(event) => onQuery(event.target.value)}
              className="pl:w-full pl:rounded-lg pl:border-0 pl:bg-[#2d2d2d] pl:py-3 pl:pr-11 pl:pl-10 pl:text-base pl:text-white pl:transition-all pl:focus:outline-none pl:focus:ring-2 pl:focus:ring-[#ff5722]"
            />
            {query && (
              <button
                className={`${ui.iconButton} pl:absolute pl:top-0.5 pl:right-1`}
                aria-label="Limpar busca"
                onClick={() => onQuery("")}
              >
                <X size={18} />
              </button>
            )}
          </label>
        </header>
        {operations && (
          <details className="pl:mb-5 pl:rounded-xl pl:border pl:border-gray-700 pl:bg-[#2d2d2d] pl:px-4 pl:py-2">
            <summary className="pl:flex pl:min-h-11 pl:cursor-pointer pl:items-center pl:gap-2 pl:text-sm pl:font-semibold pl:text-gray-300">
              <ChevronDown size={17} className="pl:text-[#ff5722]" />Operação do
              caixa e pedidos pendentes
            </summary>
            <div className="pl:py-3">{operations}</div>
          </details>
        )}
        {notices}
        {demand}
        <div
          className="pl:mb-5 pl:flex pl:shrink-0 pl:gap-3 pl:overflow-x-auto pl:pb-2"
          role="group"
          aria-label="Categorias"
        >
          {categories.map(([id, name]) => (
            <button
              key={id}
              aria-pressed={category === id}
              className={`pl:min-h-12 pl:shrink-0 pl:rounded-full pl:border-0 pl:px-6 pl:py-2 pl:text-sm pl:font-semibold pl:transition-colors ${
                category === id
                  ? "pl:bg-[#ff5722] pl:text-white"
                  : "pl:bg-[#2d2d2d] pl:text-gray-300 pl:hover:bg-[#3d3d3d]"
              }`}
              onClick={() => onCategory(id)}
            >
              {name}
            </button>
          ))}
        </div>
        <div className="pl:mb-4 pl:flex pl:items-center pl:justify-between pl:gap-3">
          <h2 className="pl:text-base pl:font-bold pl:text-white">
            {categories.find(([id]) => id === category)?.[1]}
          </h2>
          <span className="pl:text-xs pl:text-gray-400">
            {filtered.length} de {products.length} produtos
          </span>
        </div>
        <div
          className="pl:max-h-[60dvh] pl:min-h-0 pl:flex-1 pl:overflow-y-auto pl:pr-1 pl:lg:max-h-none"
          data-catalog-scroll
        >
          <div className="pl:grid pl:grid-cols-2 pl:gap-4 pl:@min-[540px]/catalog:grid-cols-3 pl:@min-[760px]/catalog:grid-cols-4">
            {filtered.map((product) => (
              <button
                data-product-card
                key={product.id}
                disabled={frozen}
                aria-label={`Adicionar ${product.name}`}
                onClick={() => onAdd(product)}
                className="pl:group pl:flex pl:min-w-0 pl:cursor-pointer pl:flex-col pl:items-center pl:rounded-xl pl:border-0 pl:bg-[#2d2d2d] pl:p-4 pl:text-center pl:transition-all pl:hover:ring-2 pl:hover:ring-[#ff5722] pl:focus-visible:outline-none pl:focus-visible:ring-2 pl:focus-visible:ring-[#ff5722] pl:disabled:cursor-not-allowed pl:disabled:opacity-40"
              >
                <ProductImage
                  key={product.image_path || product.id}
                  product={product}
                />
                <h3 className="pl:mb-0 pl:min-h-10 pl:text-sm pl:leading-5 pl:font-bold pl:text-gray-100">
                  {product.name}
                </h3>
                <p className="pl:mt-1 pl:text-lg pl:font-black pl:text-[#ff5722]">
                  {money(product.price_cents)}
                </p>
              </button>
            ))}
          </div>
          {!filtered.length && (
            <div className="pl:flex pl:min-h-56 pl:flex-col pl:items-center pl:justify-center pl:gap-3 pl:p-6 pl:text-center">
              <Search className="pl:text-[#ff5722]" size={32} />
              <h3 className="pl:text-lg pl:font-bold">
                Nenhum produto encontrado.
              </h3>
              <p className="pl:text-sm pl:text-gray-400">
                Tente outro nome ou categoria.
              </p>
            </div>
          )}
        </div>
      </section>
      <aside
        className="pl:relative pl:z-10 pl:flex pl:w-full pl:shrink-0 pl:flex-col pl:border-t pl:border-gray-700 pl:bg-[#2d2d2d] pl:shadow-2xl pl:lg:w-96 pl:lg:border-t-0 pl:lg:border-l"
        id="pedido-atual"
        aria-label="Comanda atual"
      >
        <div className="pl:flex pl:flex-wrap pl:items-center pl:justify-between pl:gap-3 pl:border-b pl:border-gray-700 pl:bg-[#242424] pl:p-6">
          <h2 className="pl:flex pl:items-center pl:gap-2 pl:text-xl pl:font-bold">
            <ShoppingCart className="pl:text-[#ff5722]" />Comanda
          </h2>
          <span className="pl:rounded-md pl:bg-[#1a1a1a] pl:px-3 pl:py-1 pl:font-mono pl:text-sm pl:text-gray-300">
            {draft.order
              ? `#${String(draft.order.number).padStart(4, "0")}`
              : `${units} ${units === 1 ? "item" : "itens"}`}
          </span>
          <button
            className={`${ui.secondary} pl:w-full pl:lg:hidden`}
            onClick={() =>
              document.getElementById("catalogo")?.scrollIntoView({
                behavior: "smooth",
                block: "start",
              })}
          >
            <ChevronUp size={17} />Voltar ao cardápio
          </button>
        </div>
        <div className="pl:grid pl:grid-cols-2 pl:gap-3 pl:border-b pl:border-gray-700 pl:p-4">
          <label className="pl:text-xs pl:font-medium pl:text-gray-400">
            Cliente<input
              className={`${ui.input} pl:mt-2`}
              aria-label="Nome do cliente"
              value={draft.customer}
              onChange={(event) => onCustomer(event.target.value)}
              placeholder="Cliente balcão"
              maxLength={100}
              disabled={frozen}
            />
          </label>
          <label className="pl:text-xs pl:font-medium pl:text-gray-400">
            Canal<select
              aria-label="Canal do pedido"
              className={`${ui.input} pl:mt-2`}
              value={draft.channel}
              onChange={(event) => onChannel(event.target.value)}
              disabled={frozen}
            >
              <option value="counter">Balcão</option>
              <option value="whatsapp">WhatsApp · manual</option>
            </select>
          </label>
        </div>
        <div
          className="pl:flex pl:min-h-40 pl:flex-1 pl:flex-col pl:gap-3 pl:overflow-y-auto pl:p-4"
          aria-label="Itens da comanda"
          aria-live="polite"
        >
          {!draft.items.length && (
            <div className="pl:flex pl:flex-1 pl:flex-col pl:items-center pl:justify-center pl:gap-3 pl:py-8 pl:text-center">
              <ShoppingCart size={38} className="pl:text-gray-500" />
              <h3 className="pl:text-base pl:font-bold pl:text-gray-200">
                Sua comanda começa aqui.
              </h3>
              <p className="pl:max-w-56 pl:text-sm pl:leading-6 pl:text-gray-400">
                Toque nos produtos para adicionar e personalizar o pedido.
              </p>
            </div>
          )}
          {draft.items.map((item) => (
            <article
              key={item.lineId}
              data-cart-line
              className={`pl:shrink-0 pl:rounded-lg pl:border pl:bg-[#1a1a1a] pl:p-3 ${
                selected === item.lineId
                  ? "pl:border-[#ff5722]"
                  : "pl:border-gray-700"
              }`}
            >
              <div className="pl:flex pl:items-start pl:justify-between pl:gap-3">
                <button
                  className="pl:flex pl:min-h-11 pl:min-w-0 pl:flex-1 pl:flex-col pl:items-start pl:border-0 pl:bg-transparent pl:p-0 pl:text-left"
                  disabled={frozen}
                  aria-expanded={selected === item.lineId}
                  onClick={() =>
                    onSelect(selected === item.lineId ? null : item.lineId)}
                >
                  <strong className="pl:text-sm pl:leading-6 pl:font-bold pl:text-gray-100">
                    {item.quantity}x {item.name}
                  </strong>
                  <span className="pl:mt-1 pl:text-xs pl:leading-5 pl:text-gray-400">
                    {item.modifiers.length
                      ? item.modifiers.map((m) => `− ${m}`).join(" · ")
                      : "Personalizar item"}
                    {selected === item.lineId
                      ? <ChevronUp size={14} className="pl:ml-1 pl:inline" />
                      : <ChevronDown size={14} className="pl:ml-1 pl:inline" />}
                  </span>
                </button>
                <div className="pl:flex pl:shrink-0 pl:flex-col pl:items-end">
                  <strong className="pl:whitespace-nowrap pl:text-sm pl:font-bold pl:text-[#ff5722]">
                    {money(item.quantity * item.price_cents)}
                  </strong>
                  <button
                    className={ui.removeButton}
                    aria-label={`Remover ${item.name}`}
                    disabled={frozen}
                    onClick={() =>
                      onUpdate(item.lineId, { quantity: 0 })}
                  >
                    <Trash2 size={17} />
                  </button>
                </div>
              </div>
              <div className="pl:mt-3 pl:flex pl:w-fit pl:items-center pl:gap-2 pl:rounded-lg pl:border pl:border-gray-700">
                <button
                  className={ui.iconButton}
                  aria-label={`Diminuir ${item.name}`}
                  disabled={frozen}
                  onClick={() =>
                    onUpdate(item.lineId, { quantity: item.quantity - 1 })}
                >
                  <Minus size={16} />
                </button>
                <span className="pl:min-w-6 pl:text-center pl:text-sm pl:font-bold">
                  {item.quantity}
                </span>
                <button
                  className={ui.iconButton}
                  aria-label={`Aumentar ${item.name}`}
                  disabled={frozen || item.quantity >= 100}
                  onClick={() =>
                    onUpdate(item.lineId, { quantity: item.quantity + 1 })}
                >
                  <Plus size={16} />
                </button>
              </div>
              {selected === item.lineId && (
                <div
                  data-inline-modifiers
                  className="pl:mt-4 pl:border-t pl:border-gray-700 pl:pt-3"
                >
                  <p className="pl:mb-3 pl:text-xs pl:font-semibold pl:text-gray-400">
                    DO JEITO DO CLIENTE
                  </p>
                  <div className="pl:flex pl:flex-wrap pl:gap-2">
                    {(item.allowed_modifiers || []).map((modifier) => (
                      <button
                        key={modifier}
                        aria-pressed={item.modifiers.includes(modifier)}
                        className={`pl:inline-flex pl:min-h-11 pl:items-center pl:gap-1 pl:rounded-lg pl:border pl:px-2 pl:py-2 pl:text-xs pl:font-semibold pl:transition-colors ${
                          item.modifiers.includes(modifier)
                            ? "pl:border-[#ff5722] pl:bg-[#ff5722]/15 pl:text-[#ff5722]"
                            : "pl:border-gray-700 pl:bg-[#2d2d2d] pl:text-gray-300 pl:hover:border-[#ff5722]"
                        }`}
                        disabled={frozen}
                        onClick={() =>
                          onUpdate(item.lineId, {
                            modifiers: toggleModifier(item.modifiers, modifier),
                          })}
                      >
                        {item.modifiers.includes(modifier) && (
                          <Check size={13} />
                        )}
                        {modifier}
                      </button>
                    ))}
                  </div>
                  <textarea
                    aria-label={`Observações de ${item.name}`}
                    className={`${ui.input} pl:mt-3 pl:min-h-20 pl:resize-y`}
                    placeholder="Algum detalhe para a cozinha?"
                    value={item.notes}
                    disabled={frozen}
                    maxLength={500}
                    onChange={(event) =>
                      onUpdate(item.lineId, { notes: event.target.value })}
                  />
                </div>
              )}
            </article>
          ))}
        </div>
        <div className="pl:max-h-[55vh] pl:shrink-0 pl:overflow-y-auto pl:border-t pl:border-gray-700 pl:bg-[#1a1a1a] pl:p-6">
          <div className="pl:mb-2 pl:flex pl:items-center pl:justify-between pl:gap-3 pl:text-sm pl:text-gray-400">
            <span>Subtotal</span>
            <span>{money(subtotal)}</span>
          </div>
          {subtotal > total && (
            <div className="pl:mb-2 pl:flex pl:justify-between pl:text-sm pl:text-gray-400">
              <span>Desconto</span>
              <span>− {money(subtotal - total)}</span>
            </div>
          )}
          <div className="pl:mb-6 pl:flex pl:items-center pl:justify-between pl:gap-3 pl:text-2xl pl:font-black pl:text-white">
            <span>Total</span>
            <span data-cart-total className="pl:text-[#ff5722]">
              {money(total)}
            </span>
          </div>
          <div className="pl-payment-body">{paymentActions}</div>
        </div>
      </aside>
    </div>
  );
}
