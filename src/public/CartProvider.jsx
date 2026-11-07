import { useEffect, useState } from "react";
import { CartContext, draftLine, patchCart } from "./cart";
function restore() {
  try {
    const value = JSON.parse(
      sessionStorage.getItem("planeta:online:cart") || "[]",
    );
    return Array.isArray(value) && value.length <= 30
      ? value.filter(
          (i) =>
            i &&
            typeof i.line_id === "string" &&
            typeof i.product_id === "string" &&
            Number.isInteger(i.quantity) &&
            i.quantity > 0 &&
            i.quantity <= 100 &&
            Number.isSafeInteger(i.price_cents) &&
            Array.isArray(i.modifiers) &&
            i.modifiers.every((m) => typeof m === "string") &&
            typeof i.notes === "string",
        )
      : [];
  } catch {
    return [];
  }
}
export default function CartProvider({ children }) {
  const [items, setItems] = useState(restore);
  useEffect(() => {
    try {
      sessionStorage.setItem("planeta:online:cart", JSON.stringify(items));
    } catch {
      /* Carrinho continua em memória. */
    }
  }, [items]);
  function add(product) {
    setItems((previous) => {
      const identical = previous.find(
        (i) =>
          i.product_id === (product.product_id || product.id) &&
          !i.modifiers.length &&
          !i.notes &&
          i.quantity < 100,
      );
      if (identical)
        return patchCart(previous, identical.line_id, {
          quantity: identical.quantity + 1,
        });
      return previous.length < 30
        ? [...previous, draftLine(product)]
        : previous;
    });
  }
  return (
    <CartContext.Provider
      value={{
        items,
        setItems,
        add,
        update: (id, patch) => setItems((p) => patchCart(p, id, patch)),
        clear: () => setItems([]),
      }}
    >
      {children}
    </CartContext.Provider>
  );
}
