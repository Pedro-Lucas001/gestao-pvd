/** Implement one adapter after choosing a contracted provider. Never accept an
 * amount or paid flag from a browser; use the persisted payment attempt. */
export type PaymentIntent = {
  providerReference: string;
  status: "pending";
  pix?: { copyPaste: string; expiresAt: string };
  terminalMessage?: string;
};
export type VerifiedPayment = {
  eventId: string;
  attemptId: string;
  amountCents: number;
  providerReference: string;
  provider: string;
  payloadHash: string;
};
export interface Gateway {
  createIntent(input: {
    attemptId: string;
    amountCents: number;
    method: "pix" | "tef";
  }): Promise<PaymentIntent>;
  verifyWebhook(
    rawBody: Uint8Array,
    headers: Headers,
  ): Promise<VerifiedPayment>;
}
export function gateway(): Gateway {
  // Fail closed. A provider integration must implement signature validation,
  // replay/expiry checks, currency=BRL and stable provider idempotency keys.
  throw new Error("PAYMENT_GATEWAY_NOT_CONFIGURED");
}
