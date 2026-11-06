import { createClient } from "npm:@supabase/supabase-js@2.99.0";
import { gateway } from "../_shared/gateway.ts";
import { cors, response, readLimited } from "../_shared/http.ts";
Deno.serve(async (req: Request) => {
  const headers = cors(req);
  if (!headers) return response({ error: "ORIGIN_NOT_ALLOWED" }, 403);
  const reply = (body: unknown, status = 200) => {
    const r = response(body, status);
    for (const [k, v] of Object.entries(headers)) r.headers.set(k, v);
    return r;
  };
  if (req.method === "OPTIONS") return reply({ ok: true });
  if (req.method !== "POST") return reply({ error: "METHOD_NOT_ALLOWED" }, 405);
  try {
    const { tracking, key } = JSON.parse(
      new TextDecoder().decode(await readLimited(req, 4096)),
    );
    if (
      typeof tracking !== "string" ||
      !tracking.match(/^[a-f0-9]{64}$/) ||
      typeof key !== "string"
    )
      return reply({ error: "INVALID_REQUEST" }, 400);
    const adapter = gateway();
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { data, error } = await db.rpc("prepare_checkout_payment", {
      p_tracking: tracking,
      p_key: key,
    });
    if (error || !data) return reply({ error: "PAYMENT_NOT_ALLOWED" }, 409);
    const intent = await adapter.createIntent({
      attemptId: data.id,
      amountCents: data.amount_cents,
      method: "pix",
    });
    if (intent.pix) {
      const { error } = await db.rpc("record_pix_artifact", {
        p_attempt: data.id,
        p_code: intent.pix.copyPaste,
        p_expires: intent.pix.expiresAt,
      });
      if (error)
        return reply({ error: "PIX_RESPONSE_UNCONFIRMED_RETRY_SAME_KEY" }, 502);
    }
    return reply({ attemptId: data.id, ...intent });
  } catch (e) {
    if (e instanceof RangeError)
      return reply({ error: "PAYLOAD_TOO_LARGE" }, 413);
    return reply(
      {
        error:
          e instanceof Error && e.message === "PAYMENT_GATEWAY_NOT_CONFIGURED"
            ? "Pix ainda não configurado pela loja."
            : "Não foi possível gerar o Pix. Retome a mesma tentativa.",
      },
      503,
    );
  }
});
