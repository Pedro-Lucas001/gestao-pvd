import { useEffect, useRef, useState } from "react";
import { X } from "lucide-react";
import { draftLine } from "./cart";
import { money } from "../lib/operations";
import { cartUnitPrice } from "./menuOptions";
import ProductOptions from "./ProductOptions";

export default function ProductCustomizer({
  product,
  catalog,
  onAdd,
  onClose,
  full,
}) {
  const [line, setLine] = useState(() => draftLine(product));
  const dialog = useRef(null);
  useEffect(() => {
    const element = dialog.current;
    element.showModal();
    return () => element.close();
  }, []);
  const flavorValid =
    product.category !== "coxinhas" ||
    product.allowed_modifiers?.some(
      (m) => m.startsWith("Sabor:") && line.modifiers.includes(m),
    );
  return (
    <dialog
      ref={dialog}
      className="customer-customizer menu-page"
      onCancel={onClose}
      aria-labelledby="customizer-title"
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (flavorValid && !full) {
            onAdd({ ...product, ...line });
            onClose();
          }
        }}
      >
        <header>
          <div>
            <span className="menu-section-kicker">DO SEU JEITO</span>
            <h2 id="customizer-title">{product.name}</h2>
          </div>
          <button
            type="button"
            className="customer-secondary"
            onClick={onClose}
            aria-label="Fechar personalização"
          >
            <X size={20} />
          </button>
        </header>
        <p>{product.description}</p>
        <ProductOptions
          product={product}
          line={line}
          onChange={(patch) => setLine((p) => ({ ...p, ...patch }))}
          catalog={catalog}
        />
        <label>
          Quantidade
          <input
            type="number"
            min={1}
            max={100}
            required
            value={line.quantity}
            onChange={(e) =>
              setLine((p) => ({ ...p, quantity: Number(e.target.value) }))
            }
          />
        </label>
        <label>
          Observações
          <textarea
            maxLength={500}
            value={line.notes}
            onChange={(e) => setLine((p) => ({ ...p, notes: e.target.value }))}
            placeholder="Alguma observação sobre este item?"
          />
        </label>
        {full && (
          <p role="alert">
            O carrinho já tem 30 itens diferentes. Revise seu pedido antes de
            adicionar outro.
          </p>
        )}
        <button
          className="customer-primary customer-full"
          disabled={full || !flavorValid}
        >
          Adicionar ao pedido ·{" "}
          {money(cartUnitPrice(line, catalog) * line.quantity)}
        </button>
      </form>
    </dialog>
  );
}
