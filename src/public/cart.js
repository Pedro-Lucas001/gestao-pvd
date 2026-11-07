import { createContext, useContext } from "react";
export const CartContext = createContext(null);
export const useCart = () => useContext(CartContext);
export function cartPayload(items) {
  return items.map((i) => ({ product_id: i.product_id || i.id, quantity: i.quantity, modifiers: [...(i.modifiers || [])], notes: i.notes || "" }));
}
export function trackingToken() {
  return [...crypto.getRandomValues(new Uint8Array(32))].map((n) => n.toString(16).padStart(2, "0")).join("");
}
export function operationKey() {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  const h = [...bytes].map((v) => v.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
}
export function draftLine(product, quantity = 1) {
  return { line_id: operationKey(), product_id: product.product_id || product.id, name: product.name, price_cents: product.price_cents ?? product.unit_price_cents, quantity, modifiers: [...(product.modifiers || [])], notes: product.notes || "" };
}
export function patchCart(items, lineId, patch) {
  return items.map((i) => i.line_id === lineId ? { ...i, ...patch } : i).filter((i) => Number.isInteger(i.quantity) && i.quantity > 0 && i.quantity <= 100);
}
