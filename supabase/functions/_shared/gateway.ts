import { brCode } from "./pix.ts";
export type PaymentIntent = {
  providerReference: string;
  status: "pending";
  confirmation: "manual_admin" | "provider_webhook";
  pix?: { copyPaste: string; expiresAt: string | null };
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
  supports: readonly string[];
  createIntent(input: {
    attemptId: string;
    amountCents: number;
    method: "pix" | "tef";
  }): Promise<PaymentIntent>;
  verifyWebhook(raw: Uint8Array, headers: Headers): Promise<VerifiedPayment>;
}
export class ManualPix implements Gateway {
  supports = ["pix"];
  constructor(private merchant: { key: string; name: string; city: string }) {}
  async createIntent(input: {
    attemptId: string;
    amountCents: number;
    method: "pix" | "tef";
  }): Promise<PaymentIntent> {
    if (input.method !== "pix") throw new Error("TEF_NOT_CONFIGURED");
    return {
      providerReference: "manual-pix-intent:" + input.attemptId,
      status: "pending",
      confirmation: "manual_admin",
      pix: {
        copyPaste: brCode({
          ...this.merchant,
          amountCents: input.amountCents,
          txid: input.attemptId.replace(/-/g, "").slice(0, 25),
        }),
        expiresAt: null,
      },
    };
  }
  async verifyWebhook(
    _raw: Uint8Array,
    _headers: Headers,
  ): Promise<VerifiedPayment> {
    throw new Error("MANUAL_PIX_REQUIRES_ADMIN_VERIFICATION");
  }
}
export function gateway(config?: {
  mode?: string;
  key?: string;
  name?: string;
  city?: string;
}): Gateway {
  const values = config || {
    mode: Deno.env.get("PAYMENT_MODE"),
    key: Deno.env.get("PIX_KEY"),
    name: Deno.env.get("PIX_MERCHANT_NAME"),
    city: Deno.env.get("PIX_MERCHANT_CITY"),
  };
  const { mode, key, name, city } = values;
  if (mode === "manual_pix" && key && name && city) {
    try {
      brCode({ key, name, city, amountCents: 1, txid: "CONFIGCHECK" });
      return new ManualPix({ key, name, city });
    } catch {
      throw new Error("PAYMENT_GATEWAY_NOT_CONFIGURED");
    }
  }
  throw new Error("PAYMENT_GATEWAY_NOT_CONFIGURED");
}
