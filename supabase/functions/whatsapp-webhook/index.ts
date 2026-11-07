import { kickWorker } from "../_shared/kick_worker.ts";
import { createClient } from "npm:@supabase/supabase-js@2.99.0";
import { response, readLimited } from "../_shared/http.ts";
import { hmacValid, sameSecret } from "../_shared/meta.ts";
Deno.serve(async (req: Request) => {
  const url = new URL(req.url),
    verify = Deno.env.get("WHATSAPP_VERIFY_TOKEN") || "";
  if (req.method === "GET") {
    if (
      url.searchParams.get("hub.mode") === "subscribe" &&
      (await sameSecret(url.searchParams.get("hub.verify_token") || "", verify))
    )
      return new Response(url.searchParams.get("hub.challenge") || "", {
        headers: { "Content-Type": "text/plain" },
      });
    return response({ error: "CHALLENGE_DENIED" }, 403);
  }
  if (req.method !== "POST")
    return response({ error: "METHOD_NOT_ALLOWED" }, 405);
  const secret = Deno.env.get("WHATSAPP_APP_SECRET"),
    phone = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  if (!secret || !phone)
    return response({ error: "WHATSAPP_NOT_CONFIGURED" }, 503);
  try {
    const raw = await readLimited(req);
    if (!(await hmacValid(raw, req.headers.get("X-Hub-Signature-256"), secret)))
      return response({ error: "INVALID_SIGNATURE" }, 401);
    const payload = JSON.parse(new TextDecoder().decode(raw));
    if (payload.object !== "whatsapp_business_account")
      return response({ error: "INVALID_OBJECT" }, 400);
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    for (const entry of (payload.entry || []).slice(0, 20))
      for (const change of (entry.changes || []).slice(0, 20)) {
        const value = change.value;
        if (value?.metadata?.phone_number_id !== phone) continue;
        for (const m of (value.messages || []).slice(0, 20)) {
          if (m.type !== "text") continue;
          const seconds = Number(m.timestamp);
          if (!Number.isFinite(seconds) || seconds * 1000 > Date.now() + 300000)
            return response({ error: "INVALID_TIMESTAMP" }, 400);
          const { error } = await db.rpc("ingest_whatsapp", {
            p_id: m.id,
            p_sender: m.from,
            p_text: m.text?.body,
            p_received: new Date(seconds * 1000).toISOString(),
          });
          if (error)
            return response({ error: "INGESTION_RETRY_REQUIRED" }, 503);
        }
      }
    kickWorker();
    return response({ ok: true });
  } catch (e) {
    return response(
      {
        error:
          e instanceof RangeError ? "PAYLOAD_TOO_LARGE" : "INVALID_PAYLOAD",
      },
      e instanceof RangeError ? 413 : 400,
    );
  }
});
