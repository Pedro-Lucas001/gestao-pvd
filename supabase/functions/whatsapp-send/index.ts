import { createClient } from "npm:@supabase/supabase-js@2.99.0";
import { cors, response, readLimited } from "../_shared/http.ts";
import { MetaClient } from "../_shared/meta.ts";
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
  const client = createClient(
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
    error: authError,
  } = await client.auth.getUser();
  if (authError || !user) return reply({ error: "AUTH_REQUIRED" }, 401);
  try {
    const { inboxId, text } = JSON.parse(
      new TextDecoder().decode(await readLimited(req, 8192)),
    );
    if (
      typeof text !== "string" ||
      text.trim().length < 1 ||
      text.length > 2000
    )
      return reply({ error: "INVALID_TEXT" }, 400);
    const { data: message, error } = await client
      .from("whatsapp_inbox")
      .select("id,sender,received_at")
      .eq("id", inboxId)
      .single();
    if (error || !message)
      return reply({ error: "CONVERSATION_NOT_AUTHORIZED" }, 403);
    if (new Date(message.received_at).getTime() < Date.now() - 23 * 3600000)
      return reply(
        { error: "CONVERSATION_WINDOW_EXPIRED_USE_APPROVED_TEMPLATE" },
        409,
      );
    const token = Deno.env.get("WHATSAPP_ACCESS_TOKEN"),
      phone = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
    if (!token || !phone)
      return reply({ error: "WHATSAPP_API_NOT_CONFIGURED" }, 503);
    const meta = new MetaClient(
      token,
      phone,
      Deno.env.get("WHATSAPP_GRAPH_VERSION") || "v23.0",
    );
    const id = await meta.text(message.sender, text.trim());
    const trusted = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { error: record } = await trusted.rpc("record_whatsapp_reply", {
      p_id: inboxId,
      p_actor: user.id,
    });
    if (record)
      return reply(
        { error: "SENT_AUDIT_UNCONFIRMED_DO_NOT_RESEND", sent: true },
        502,
      );
    return reply({ ok: true, id });
  } catch {
    return reply(
      { error: "SEND_UNCONFIRMED_CHECK_CONVERSATION_BEFORE_RETRY" },
      502,
    );
  }
});
