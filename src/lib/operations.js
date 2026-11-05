export const money = (n) =>
  (n / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
export const normalize = (s) =>
  s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
export function cents(value) {
  if (!/^\d{1,7}([.,]\d{1,2})?$/.test(value))
    throw new Error("Informe um valor válido, com até duas casas decimais.");
  const [whole, decimal = ""] = value.replace(",", ".").split(".");
  return Number(whole) * 100 + Number(decimal.padEnd(2, "0"));
}
export function urgency(createdAt, now = Date.now()) {
  const minutes = Math.max(0, (now - new Date(createdAt).getTime()) / 60000);
  return minutes > 20 ? "critical" : minutes >= 10 ? "warning" : "normal";
}
export function toggleModifier(current, value) {
  if (current.includes(value)) return current.filter((x) => x !== value);
  return [
    ...current.filter(
      (x) => !value.startsWith("Ponto:") || !x.startsWith("Ponto:"),
    ),
    value,
  ];
}
export function orderPayload(draft) {
  return {
    p_key: draft.key,
    p_customer: draft.customer.trim() || "Cliente balcão",
    p_channel: draft.channel,
    p_items: draft.items.map((i) => ({
      product_id: i.id,
      quantity: i.quantity,
      modifiers: i.modifiers,
      notes: i.notes,
    })),
  };
}
export function emptyDraft() {
  return {
    key: crypto.randomUUID(),
    customer: "",
    channel: "counter",
    items: [],
    order: null,
    paymentKeys: {
      cash: crypto.randomUUID(),
      pix: crypto.randomUUID(),
      tef: crypto.randomUUID(),
    },
    payment: null,
  };
}

export function oneRecord(data) {
  const value = Array.isArray(data) && data.length === 1 ? data[0] : data;
  if (!value || Array.isArray(value) || typeof value.id !== "string")
    throw new Error(
      "Resposta do servidor não pôde ser confirmada. Reenvie a mesma tentativa.",
    );
  return value;
}
