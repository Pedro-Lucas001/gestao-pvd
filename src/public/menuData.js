import { normalize } from "../lib/operations.js";

export function publicProducts(data) {
  if (!Array.isArray(data)) throw new Error("Cardápio inválido.");
  return data.map((product) => {
    if (
      !product ||
      typeof product.id !== "string" ||
      typeof product.name !== "string" ||
      typeof product.category !== "string" ||
      !Number.isSafeInteger(product.price_cents) ||
      product.price_cents <= 0
    ) {
      throw new Error("Cardápio inválido.");
    }
    // Nunca renderiza dados operacionais extras, mesmo em uma resposta alterada.
    return {
      id: product.id,
      name: product.name,
      category: product.category,
      description:
        typeof product.description === "string" ? product.description : "",
      price_cents: product.price_cents,
      image_path:
        typeof product.image_path === "string" ? product.image_path : "",
    };
  });
}

export function filterMenu(products, category, query) {
  const search = normalize(query.trim());
  return products.filter(
    (p) =>
      (category === "all" || p.category === category) &&
      normalize(`${p.name} ${p.description}`).includes(search),
  );
}
