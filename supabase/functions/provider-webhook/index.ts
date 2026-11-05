import { createClient } from "npm:@supabase/supabase-js@2.99.0";
import { gateway } from "../_shared/gateway.ts";
import { response, readLimited } from "../_shared/http.ts";
Deno.serve(async (req: Request) => {
  if (req.method !== "POST")
    return response({ error: "METHOD_NOT_ALLOWED" }, 405);
  if (Number(req.headers.get("Content-Length") || 0) > 65536)
    return response({ error: "PAYLOAD_TOO_LARGE" }, 413);
  try {
    const adapter = gateway();
    const raw = await readLimited(req);
    if (raw.byteLength > 65536)
      return response({ error: "PAYLOAD_TOO_LARGE" }, 413);
    // No mutation is possible until the contracted provider authenticates its
    // signature against the RAW bytes, timestamp and merchant account.
    const event = await adapter.verifyWebhook(raw, req.headers);
    const client = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { error } = await client.rpc("confirm_provider_payment", {
      p_attempt: event.attemptId,
      p_amount: event.amountCents,
      p_reference: event.providerReference,
      p_provider: event.provider,
      p_event: event.eventId,
      p_payload_hash: event.payloadHash,
    });
    if (error) return response({ error: "EVENT_NOT_APPLIED" }, 409);
    return response({ ok: true });
  } catch (error) {
    if (error instanceof RangeError)
      return response({ error: "PAYLOAD_TOO_LARGE" }, 413);
    if (
      error instanceof Error &&
      error.message === "PAYMENT_GATEWAY_NOT_CONFIGURED"
    )
      return response({ error: "GATEWAY_NOT_CONFIGURED" }, 503);
    return response({ error: "INVALID_OR_UNVERIFIED_EVENT" }, 401);
  }
});
