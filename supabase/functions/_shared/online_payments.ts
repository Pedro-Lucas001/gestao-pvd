import { brCode } from "./pix.ts";
import { hmacValid } from "./meta.ts";
import { onlineRpc, publicSite } from "./online.ts";
export type OnlinePayment = {
  id: string;
  order_id: string;
  number: number;
  amount_cents: number;
  method: "pix" | "card";
  status: string;
  email: string;
  provider_reference?: string;
  checkout_url?: string;
  pix_code?: string;
  expires_at?: string;
};
export type PaymentArtifact = {
  provider: string;
  reference: string | null;
  url: string | null;
  pix: string | null;
  expires: string | null;
};

export function paymentCapabilities() {
  const mp = Boolean(
    Deno.env.get("MERCADOPAGO_ACCESS_TOKEN") &&
    Deno.env.get("MERCADOPAGO_COLLECTOR_ID") &&
    Deno.env.get("MERCADOPAGO_WEBHOOK_SECRET") &&
    Deno.env.get("PUBLIC_SITE_URL"),
  );
  const manual =
    Deno.env.get("PAYMENT_MODE") === "manual_pix" &&
    Boolean(
      Deno.env.get("PIX_KEY") &&
      Deno.env.get("PIX_MERCHANT_NAME") &&
      Deno.env.get("PIX_MERCHANT_CITY"),
    );
  return { pix: mp || manual, card: mp, manual_pix: !mp && manual };
}
async function mpRequest(path: string, init: RequestInit = {}) {
  const response = await fetch(`https://api.mercadopago.com${path}`, {
    ...init,
    signal: AbortSignal.timeout(15000),
    headers: {
      Authorization: `Bearer ${Deno.env.get("MERCADOPAGO_ACCESS_TOKEN")}`,
      "Content-Type": "application/json",
      ...init.headers,
    },
  });
  if (!response.ok) throw new Error(`PAYMENT_PROVIDER_HTTP_${response.status}`);
  return response.json();
}
export function amountInCents(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  const cents = Math.round(n * 100);
  if (
    !Number.isFinite(n) ||
    cents <= 0 ||
    !Number.isSafeInteger(cents) ||
    Math.abs(n * 100 - cents) > 0.00001
  )
    throw new Error("INVALID_PROVIDER_AMOUNT");
  return cents;
}
export function safeCheckoutUrl(value: unknown): string {
  const url = new URL(String(value));
  if (
    url.protocol !== "https:" ||
    ![
      "www.mercadopago.com.br",
      "sandbox.mercadopago.com.br",
      "mercadopago.com.br",
      "www.mercadopago.com",
      "mercadopago.com",
    ].includes(url.hostname) ||
    url.username ||
    url.password
  )
    throw new Error("INVALID_CHECKOUT_URL");
  return url.href;
}
export async function createOnlineArtifact(
  payment: OnlinePayment,
  recover: boolean,
): Promise<PaymentArtifact> {
  const modes = paymentCapabilities();
  if (payment.method === "pix" && modes.manual_pix) {
    return {
      provider: "manual_pix",
      reference: null,
      url: null,
      expires: null,
      pix: brCode({
        key: Deno.env.get("PIX_KEY")!,
        name: Deno.env.get("PIX_MERCHANT_NAME")!,
        city: Deno.env.get("PIX_MERCHANT_CITY")!,
        amountCents: payment.amount_cents,
        txid: payment.id.replace(/-/g, "").slice(0, 25),
      }),
    };
  }
  if (!modes[payment.method]) throw new Error("PAYMENT_NOT_CONFIGURED");
  const notification = `${Deno.env.get("SUPABASE_URL")}/functions/v1/online-payment-webhook`;
  if (payment.method === "pix") {
    if (!payment.email || !payment.email.includes("@"))
      throw new Error("EMAIL_REQUIRED");
    const result = await mpRequest("/v1/payments", {
      method: "POST",
      headers: { "X-Idempotency-Key": payment.id },
      body: JSON.stringify({
        transaction_amount: payment.amount_cents / 100,
        description: `Planeta Lanches · Pedido online #${payment.number}`,
        payment_method_id: "pix",
        payer: { email: payment.email },
        external_reference: payment.id,
        notification_url: notification,
      }),
    });
    const pix = result.point_of_interaction?.transaction_data?.qr_code;
    if (
      typeof pix !== "string" ||
      !pix ||
      amountInCents(result.transaction_amount) !== payment.amount_cents
    )
      throw new Error("PIX_UNCONFIRMED");
    return {
      provider: "mercadopago",
      reference: `mp:${result.id}`,
      url: null,
      pix,
      expires: result.date_of_expiration || null,
    };
  }
  // Uma preferência com resultado de criação desconhecido não é recriada cegamente.
  let result;
  if (recover) {
    const search = await mpRequest(
      `/checkout/preferences/search?external_reference=${encodeURIComponent(payment.id)}`,
    );
    if (!Array.isArray(search.elements) || search.elements.length !== 1)
      throw new Error("CARD_CREATION_REQUIRES_RECONCILIATION");
    result = await mpRequest(
      `/checkout/preferences/${encodeURIComponent(search.elements[0].id)}`,
    );
  } else {
    const back = `${publicSite()}/pedido`;
    result = await mpRequest("/checkout/preferences", {
      method: "POST",
      headers: { "X-Idempotency-Key": payment.id },
      body: JSON.stringify({
        external_reference: payment.id,
        notification_url: notification,
        items: [
          {
            id: payment.id,
            title: `Pedido online #${payment.number}`,
            currency_id: "BRL",
            quantity: 1,
            unit_price: payment.amount_cents / 100,
          },
        ],
        payer: { email: payment.email },
        back_urls: { success: back, pending: back, failure: back },
        payment_methods: {
          excluded_payment_types: [
            { id: "ticket" },
            { id: "bank_transfer" },
            { id: "atm" },
          ],
          installments: 1,
        },
      }),
    });
  }
  return {
    provider: "mercadopago",
    reference: null,
    url: safeCheckoutUrl(
      Deno.env.get("MERCADOPAGO_LIVE_MODE") === "true"
        ? result.init_point
        : result.sandbox_init_point,
    ),
    pix: null,
    expires: null,
  };
}
export async function ensureOnlineIntent(
  payment: OnlinePayment,
): Promise<PaymentArtifact> {
  if (payment.pix_code || payment.checkout_url)
    return {
      provider: "stored",
      reference: payment.provider_reference || null,
      url: payment.checkout_url || null,
      pix: payment.pix_code || null,
      expires: payment.expires_at || null,
    };
  const state = await onlineRpc<string>("online_claim_payment_creation", {
    p_payment: payment.id,
  });
  if (state === "busy" || state === "ready")
    throw new Error("PAYMENT_GENERATING_RETRY_SAME_ATTEMPT");
  try {
    const artifact = await createOnlineArtifact(payment, state === "recover");
    await onlineRpc("online_record_artifact", {
      p_payment: payment.id,
      p_provider: artifact.provider,
      p_reference: artifact.reference,
      p_url: artifact.url,
      p_pix: artifact.pix,
      p_expires: artifact.expires,
    });
    return artifact;
  } catch (error) {
    await onlineRpc("online_uncertain_payment", { p_payment: payment.id });
    throw error;
  }
}
export async function verifyMercadoSignature(
  url: URL,
  headers: Headers,
  secret: string,
): Promise<string> {
  const id = url.searchParams.get("data.id") || "",
    requestId = headers.get("x-request-id") || "";
  const parts = Object.fromEntries(
    (headers.get("x-signature") || "")
      .split(",")
      .map((x) => x.trim().split("=")),
  );
  if (
    !/^\d{1,30}$/.test(id) ||
    !requestId ||
    requestId.length > 200 ||
    !/^\d{10,16}$/.test(parts.ts || "") ||
    !/^[a-f0-9]{64}$/i.test(parts.v1 || "")
  )
    throw new Error("INVALID_WEBHOOK_SIGNATURE");
  const manifest = `id:${id};request-id:${requestId};ts:${parts.ts};`;
  if (
    !(await hmacValid(
      new TextEncoder().encode(manifest),
      `sha256=${parts.v1}`,
      secret,
    ))
  )
    throw new Error("INVALID_WEBHOOK_SIGNATURE");
  return id;
}
export async function verifiedMercadoPayment(id: string) {
  const payment = await mpRequest(`/v1/payments/${id}`);
  if (
    String(payment.id) !== id ||
    String(payment.collector_id) !== Deno.env.get("MERCADOPAGO_COLLECTOR_ID") ||
    payment.currency_id !== "BRL" ||
    Boolean(payment.live_mode) !==
      (Deno.env.get("MERCADOPAGO_LIVE_MODE") === "true")
  )
    throw new Error("PAYMENT_ACCOUNT_MISMATCH");
  return payment;
}
