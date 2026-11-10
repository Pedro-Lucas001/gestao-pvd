import { Plus, Minus, Trash2 } from "lucide-react";
import { money } from "../lib/operations";
import { draftLine, patchCart } from "./cart";
import { cartUnitPrice } from "./menuOptions";
import ProductOptions from "./ProductOptions";
export default function CartEditor({
  items,
  setItems,
  catalog,
  disabled = false,
  allowAdd = false,
}) {
  return (
    <div className="customer-cart-editor">
      {items.map((item) => {
        const product = catalog.find(
          (p) => (p.product_id || p.id) === item.product_id,
        );
        return (
          <article className="customer-cart-line" key={item.line_id}>
            <div>
              <h3>{item.name}</h3>
              <strong>
                {money(cartUnitPrice(item, catalog) * item.quantity)}
              </strong>
            </div>
            <div className="quantity-controls">
              <button
                type="button"
                disabled={disabled}
                aria-label={`Diminuir ${item.name}`}
                onClick={() =>
                  setItems((p) =>
                    patchCart(p, item.line_id, { quantity: item.quantity - 1 }),
                  )
                }
              >
                <Minus size={16} />
              </button>
              <span>{item.quantity}</span>
              <button
                type="button"
                disabled={disabled || item.quantity >= 100}
                aria-label={`Aumentar ${item.name}`}
                onClick={() =>
                  setItems((p) =>
                    patchCart(p, item.line_id, { quantity: item.quantity + 1 }),
                  )
                }
              >
                <Plus size={16} />
              </button>
              <button
                type="button"
                disabled={disabled}
                aria-label={`Remover ${item.name}`}
                onClick={() =>
                  setItems((p) => p.filter((i) => i.line_id !== item.line_id))
                }
              >
                <Trash2 size={16} />
              </button>
            </div>
            <ProductOptions
              product={product}
              line={item}
              catalog={catalog}
              disabled={disabled}
              onChange={(patch) =>
                setItems((p) => patchCart(p, item.line_id, patch))
              }
            />
            <label>
              Observações de {item.name}
              <textarea
                disabled={disabled}
                value={item.notes}
                maxLength={500}
                placeholder="Ex.: sem molhos. Não informe dados pessoais aqui."
                onChange={(e) =>
                  setItems((p) =>
                    patchCart(p, item.line_id, { notes: e.target.value }),
                  )
                }
              />
            </label>
          </article>
        );
      })}
      {allowAdd && (
        <label>
          Adicionar outro produto
          <select
            disabled={disabled || items.length >= 30}
            value=""
            onChange={(e) => {
              const product = catalog.find(
                (p) => p.product_id === e.target.value,
              );
              if (product) setItems((p) => [...p, draftLine(product)]);
            }}
          >
            <option value="">Selecione uma opção</option>
            {catalog
              .filter((p) => p.category !== "adicionais")
              .map((p) => (
                <option key={p.product_id} value={p.product_id}>
                  {p.name} · {money(p.price_cents)}
                </option>
              ))}
          </select>
        </label>
      )}
    </div>
  );
}
