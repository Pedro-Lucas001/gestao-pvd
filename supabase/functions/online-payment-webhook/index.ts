import { readLimited, response } from "../_shared/http.ts";
import { onlineRpc, sha256 } from "../_shared/online.ts";
import { amountInCents, verifiedMercadoPayment, verifyMercadoSignature } from "../_shared/online_payments.ts";
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return response({ error: "METHOD_NOT_ALLOWED" }, 405);
  try {
    const secret = Deno.env.get("MERCADOPAGO_WEBHOOK_SECRET");
    if (!secret) return response({ error: "PAYMENT_NOT_CONFIGURED" }, 503);
    await readLimited(req, 32768);
    const id = await verifyMercadoSignature(new URL(req.url), req.headers, secret);
    const payment = await verifiedMercadoPayment(id);
    if (payment.status !== "approved") return response({ ok: true, applied: false });
    if (typeof payment.external_reference !== "string" || !/^[a-f0-9-]{36}$/i.test(payment.external_reference)) throw new Error("INVALID_REFERENCE");
    const event = `${id}:${payment.status}:${payment.date_last_updated}`;
    await onlineRpc("online_confirm_payment", { p_payment: payment.external_reference, p_amount: amountInCents(payment.transaction_amount), p_reference: `mp:${id}`, p_provider: "mercadopago", p_event: event, p_hash: await sha256(event) });
    return response({ ok: true });
  } catch {
    return response({ error: "PAYMENT_UNVERIFIED_OR_CONFLICTING_RECONCILE" }, 409);
  }
});
