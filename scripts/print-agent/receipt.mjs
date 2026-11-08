const safe = (value) => String(value ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").trim();
const money = (value) => {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("INVALID_RECEIPT_AMOUNT");
  return (value / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
};
export function receiptText(order, columns = 42) {
  if (![32, 42].includes(columns) || !Array.isArray(order.items)) throw new Error("INVALID_RECEIPT");
  const lines = ["PLANETA LANCHES", "COMANDA - NAO E DOCUMENTO FISCAL", ...(order.reprint ? ["*** SEGUNDA VIA ***"] : []),
    `PEDIDO #${safe(order.number)} / REV ${safe(order.revision)}`,
    new Date(order.created_at).toLocaleString("pt-BR", { timeZone: "America/Recife" }),
    order.fulfillment === "delivery" ? "ENTREGA" : "RETIRADA", "-".repeat(columns)];
  for (const item of order.items) {
    lines.push(`${safe(item.quantity)}x ${safe(item.name)} ${money(item.quantity * item.unit_price_cents)}`);
    if (item.modifiers?.length) lines.push(`  Alteracoes: ${item.modifiers.map(safe).join(", ")}`);
    if (item.notes) lines.push(`  Obs: ${safe(item.notes)}`);
  }
  if (order.change_note) lines.push(`REVISAO ACEITA: ${safe(order.change_note)}`);
  lines.push("-".repeat(columns), `Produtos: ${money(order.subtotal_cents)}`, `Entrega: ${money(order.delivery_fee_cents)}`);
  if (order.card_fee_cents > 0) lines.push(`Acrescimo cartao (6%): ${money(order.card_fee_cents)}`);
  lines.push(`TOTAL: ${money(order.total_cents)}`, `Recebido: ${money(order.paid_cents)}`, `A COBRAR: ${money(order.due_cents)}`);
  if (order.payment_method === "card_delivery") lines.push("*** LEVAR MAQUINETA ***", "CARTAO NA ENTREGA: CREDITO OU DEBITO", "6% JA INCLUIDOS NO TOTAL");
  else if (order.payment_method === "cash") {
    lines.push("DINHEIRO");
    if (order.cash_change_for_cents) {
      lines.push(`Troco para: ${money(order.cash_change_for_cents)}`);
      lines.push(order.cash_change_for_cents >= order.due_cents ? `Levar troco: ${money(order.cash_change_for_cents - order.due_cents)}` : "TOTAL ALTERADO: CONFIRMAR TROCO");
    } else lines.push("Cliente informou: sem troco");
  } else lines.push(order.payment_method === "pix" ? "PIX" : "CARTAO ONLINE");
  lines.push(order.due_cents > 0 ? "PAGAMENTO PENDENTE - CONFERIR RECEBIMENTO" : "PAGAMENTO CONFIRMADO", "-".repeat(columns),
    `Cliente: ${safe(order.contact?.name)}`, `WhatsApp: ${safe(order.contact?.phone)}`);
  if (order.fulfillment === "delivery") lines.push(`Endereco: ${safe(order.contact?.address)}`, `Referencia: ${safe(order.contact?.reference)}`);
  // User input is printed strictly as text, with control characters removed.
  return lines.flatMap((line) => {
    const words = line.split(/\s+/), wrapped = []; let current = "";
    for (let word of words) {
      while (word.length > columns) { if (current) { wrapped.push(current); current = ""; } wrapped.push(word.slice(0, columns)); word = word.slice(columns); }
      if (current && current.length + word.length + 1 > columns) { wrapped.push(current); current = ""; }
      current += `${current ? " " : ""}${word}`;
    }
    if (current) wrapped.push(current);
    return wrapped.length ? wrapped : [""];
  }).join("\n") + "\n";
}
