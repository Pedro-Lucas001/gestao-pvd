import { createClient } from "npm:@supabase/supabase-js@2.99.0";
import { gateway } from "../_shared/gateway.ts";
import { response, cors, readLimited } from "../_shared/http.ts";
Deno.serve(async (req: Request) => {
  const headers = cors(req);
  if (!headers) return response({ error: "ORIGIN_NOT_ALLOWED" }, 403);
  const reply = (data: unknown, status = 200) => {
    const res = response(data, status);
    for (const [k, v] of Object.entries(headers)) res.headers.set(k, v);
    return res;
  };
  if (req.method === "OPTIONS") return reply({ ok: true });
  if (req.method !== "POST") return reply({ error: "METHOD_NOT_ALLOWED" }, 405);
  const token = req.headers.get("Authorization");
  if (!token) return reply({ error: "AUTH_REQUIRED" }, 401);
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: token } } },
  );
  const {
    data: { user },
    error: authError,
  } = await client.auth.getUser();
  if (authError || !user) return reply({ error: "AUTH_REQUIRED" }, 401);
  try {
    const { orderId, method, key } = JSON.parse(
      new TextDecoder().decode(await readLimited(req, 8192)),
    );
    if (
      !["pix", "tef"].includes(method) ||
      typeof orderId !== "string" ||
      typeof key !== "string"
    )
      return reply({ error: "INVALID_REQUEST" }, 400);
    const adapter = gateway(); // Check availability before reserving an attempt.
    const { data: result, error } = await client.rpc("begin_payment", {
      p_order: orderId,
      p_method: method,
      p_key: key,
    });
    if (error) return reply({ error: "PAYMENT_NOT_ALLOWED" }, 409);
    const attempt = Array.isArray(result) ? result[0] : result;
    if (!attempt?.id)
      return reply({ error: "PAYMENT_RESPONSE_UNCONFIRMED" }, 502);
    const intent = await adapter.createIntent({
      attemptId: attempt.id,
      amountCents: attempt.amount_cents,
      method,
    });
    return reply({ attemptId: attempt.id, ...intent });
  } catch (error) {
    if (error instanceof RangeError)
      return reply({ error: "PAYLOAD_TOO_LARGE" }, 413);
    if (error instanceof SyntaxError)
      return reply({ error: "INVALID_JSON" }, 400);
    if (
      error instanceof Error &&
      error.message === "PAYMENT_GATEWAY_NOT_CONFIGURED"
    )
      return reply(
        {
          error:
            "Integração de Pix/TEF ainda não configurada. Nenhuma cobrança foi iniciada.",
        },
        503,
      );
    // No raw payloads, personal data or credentials in logs.
    return reply({ error: "PAYMENT_UNAVAILABLE_RETRY_SAME_KEY" }, 502);
  }
});
