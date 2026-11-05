import { createClient } from "npm:@supabase/supabase-js@2.99.0";
import { cors, response } from "../_shared/http.ts";
Deno.serve(async (req: Request) => {
  const headers = cors(req);
  if (!headers) return response({ error: "ORIGIN_NOT_ALLOWED" }, 403);
  const reply = (v: unknown, s = 200) => {
    const r = response(v, s);
    for (const [k, val] of Object.entries(headers)) r.headers.set(k, val);
    return r;
  };
  if (req.method === "OPTIONS") return reply({ ok: true });
  if (req.method !== "POST") return reply({ error: "METHOD_NOT_ALLOWED" }, 405);
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: {
        headers: { Authorization: req.headers.get("Authorization") || "" },
      },
    },
  );
  const {
    data: { user },
    error,
  } = await db.auth.getUser();
  if (error || !user) return reply({ error: "AUTH_REQUIRED" }, 401);
  const { data, error: profileError } = await db.rpc("operator_context");
  if (
    profileError || !data?.active || data.role !== "admin" ||
    data.requires_password
  ) {
    return reply({ error: "ADMIN_REQUIRED" }, 403);
  }
  const has = (key: string) => Boolean(Deno.env.get(key));
  return reply({
    pixConfigured: Deno.env.get("PAYMENT_MODE") === "manual_pix" &&
      ["PIX_KEY", "PIX_MERCHANT_NAME", "PIX_MERCHANT_CITY"].every(has),
    whatsappConfigured: [
      "WHATSAPP_APP_SECRET",
      "WHATSAPP_VERIFY_TOKEN",
      "WHATSAPP_ACCESS_TOKEN",
      "WHATSAPP_PHONE_NUMBER_ID",
    ].every(has),
    workerConfigured: has("INTEGRATION_WORKER_SECRET"),
    tefConfigured: false,
    liveAuthorizationVerified: false,
  });
});
