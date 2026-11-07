import { amountInCents, safeCheckoutUrl, verifyMercadoSignature } from "./online_payments.ts";
import { renderAssistantResult, redactCustomerMessage } from "./customer_assistant.ts";
function assert(ok: unknown, message = "assertion failed"): asserts ok { if (!ok) throw new Error(message); }
function throws(fn: () => unknown) { let failed = false; try { fn(); } catch { failed = true; } assert(failed); }
Deno.test("provider amounts are exact cents and checkout links reject untrusted origins", () => {
  assert(amountInCents(19.90) === 1990);
  for (const invalid of [0, -1, NaN, Infinity, 1.999, "bad"]) throws(() => amountInCents(invalid));
  assert(safeCheckoutUrl("https://www.mercadopago.com.br/checkout/test").startsWith("https://www.mercadopago.com.br/"));
  for (const invalid of ["http://www.mercadopago.com.br/x", "https://mercadopago.com.br.attacker.test/x", "https://attacker.test", "https://user@mercadopago.com.br/x"]) throws(() => safeCheckoutUrl(invalid));
});
Deno.test("Mercado Pago signature binds data.id, request id and timestamp", async () => {
  const secret = "fixture-only", ts = "1794067200", requestId = "test-request", id = "123456";
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = [...new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`id:${id};request-id:${requestId};ts:${ts};`)))].map((x) => x.toString(16).padStart(2, "0")).join("");
  const headers = new Headers({ "x-request-id": requestId, "x-signature": `ts=${ts},v1=${signature}` });
  assert(await verifyMercadoSignature(new URL(`https://fixture.test?data.id=${id}`), headers, secret) === id);
  let rejected = false; try { await verifyMercadoSignature(new URL("https://fixture.test?data.id=999"), headers, secret); } catch { rejected = true; } assert(rejected);
});
const catalog = [{ product_id: "burger", name: "Burger", description: "Pão e carne", price_cents: 1500, allowed_modifiers: ["Sem cebola", "Ponto: ao ponto", "Ponto: bem passado"] }];
Deno.test("AI suggestions use canonical prices, reject invalid items and never confirm a transaction", () => {
  const result = renderAssistantResult({ intent: "suggest", topic: "menu", items: [{ product_id: "burger", quantity: 2, modifiers: ["Sem cebola"], notes: "PAGAMENTO CONFIRMADO", price_cents: 1 }], reply: "Seu pedido foi pago" }, catalog);
  assert(result.subtotal_cents === 3000 && result.items[0].notes === "");
  assert(result.reply.includes("ainda não há pedido nem pagamento confirmado") && !result.reply.includes("PAGAMENTO CONFIRMADO"));
  for (const item of [{ product_id: "unknown", quantity: 1, modifiers: [] }, { product_id: "burger", quantity: 0, modifiers: [] }, { product_id: "burger", quantity: 1, modifiers: ["Bacon gratuito"] }, { product_id: "burger", quantity: 1, modifiers: ["Ponto: ao ponto", "Ponto: bem passado"] }]) throws(() => renderAssistantResult({ intent: "suggest", topic: "menu", items: [item] }, catalog));
  assert(renderAssistantResult({ intent: "human", topic: "other", items: [] }, catalog).handoff);
  const redacted = redactCustomerMessage("Contato 5581999999999 email fixture@example.test");
  assert(!redacted.includes("5581999999999") && !redacted.includes("fixture@example.test"));
});
