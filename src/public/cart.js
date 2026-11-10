import { createContext, useContext } from "react";
export const CartContext = createContext(null);
export const useCart = () => useContext(CartContext);
export function cartPayload(items) {
  return items.map((i) => ({
    product_id: i.product_id || i.id,
    quantity: i.quantity,
    modifiers: [...(i.modifiers || [])],
    notes: i.notes || "",
    ...(i.addons?.length ? { addons: [...i.addons] } : {}),
  }));
}
export function trackingToken() {
  return [...crypto.getRandomValues(new Uint8Array(32))]
    .map((n) => n.toString(16).padStart(2, "0"))
    .join("");
}
export function operationKey() {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  const h = [...bytes].map((v) => v.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
export function draftLine(product, quantity = 1) {
  return {
    line_id: operationKey(),
    product_id: product.product_id || product.id,
    name: product.name,
    price_cents: product.price_cents ?? product.unit_price_cents,
    quantity,
    modifiers: [...(product.modifiers || [])].filter(
      (m) => m !== "Sem acompanhamentos",
    ),
    notes: product.notes || "",
    addons: [...(product.addons || [])],
    addon_prices: [...(product.addon_prices || [])],
  };
}
export function patchCart(items, lineId, patch) {
  return items
    .map((i) => (i.line_id === lineId ? { ...i, ...patch } : i))
    .filter(
      (i) =>
        Number.isInteger(i.quantity) && i.quantity > 0 && i.quantity <= 100,
    );
}

// Rebuild the editable parent lines from the canonical order snapshot. Extra
// prices remain server snapshots; the next submission sends only their IDs.
export function orderDraft(items) {
  const parents = new Map(),
    result = [];
  items.forEach((item, index) => {
    if (item.parent_line) {
      const parent = parents.get(item.parent_line);
      if (parent) {
        parent.addons.push(item.product_id);
        parent.addon_prices.push({
          product_id: item.product_id,
          name: item.name,
          price_cents: item.unit_price_cents,
        });
      }
    } else {
      const line = draftLine(item, item.quantity);
      parents.set(index + 1, line);
      result.push(line);
    }
  });
  return result;
}
