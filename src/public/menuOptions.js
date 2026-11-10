export const sandwichCategories = ["hamburgueres", "dogoes"];
export const industrialMeatNotice =
  "Usamos carnes industrializadas. Não há escolha de ponto da carne.";
export const pastryToppings = [
  "Tomate",
  "Milho",
  "Batata palha",
  "Ketchup",
  "Maionese",
];

export function visibleModifiers(product) {
  return (product?.allowed_modifiers || []).filter(
    (m) => !m.startsWith("Ponto:") && m !== "Sem acompanhamentos",
  );
}
export function cartUnitPrice(line, catalog = []) {
  const product = catalog.find(
    (p) => (p.product_id || p.id) === line.product_id,
  );
  return (
    (product?.price_cents ?? line.price_cents ?? 0) +
    (line.addons || []).reduce((sum, id) => {
      const extra =
        catalog.find((p) => (p.product_id || p.id) === id) ||
        line.addon_prices?.find((p) => p.product_id === id);
      return sum + (extra?.price_cents || 0);
    }, 0)
  );
}
export function cartSubtotal(lines, catalog = []) {
  return lines.reduce(
    (sum, line) => sum + cartUnitPrice(line, catalog) * line.quantity,
    0,
  );
}
export function addonLabel(line) {
  return (line.addon_prices || [])
    .filter((p) => line.addons?.includes(p.product_id))
    .map((p) => p.name)
    .join(", ");
}
