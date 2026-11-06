import { readLimited } from "../_shared/http.ts";
import { hmacValid, sameSecret } from "../_shared/meta.ts";
import { ecoRpc, json, kickWorker } from "../_shared/eco.ts";
Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  if (req.method === "GET") {
    if (
      url.searchParams.get("hub.mode") === "subscribe" && await sameSecret(
        url.searchParams.get("hub.verify_token") || "",
        Deno.env.get("WHATSAPP_VERIFY_TOKEN") || "",
      )
    ) {
      return new Response(url.searchParams.get("hub.challenge") || "", {
        headers: { "Content-Type": "text/plain" },
      });
    }
    return json({ error: "CHALLENGE_DENIED" }, 403);
  }
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  const secret = Deno.env.get("WHATSAPP_APP_SECRET"),
    phoneId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  if (!secret || !phoneId) return json({ error: "NOT_CONFIGURED" }, 503);
  try {
    const raw = await readLimited(req);
    if (!await hmacValid(raw, req.headers.get("X-Hub-Signature-256"), secret)) {
      return json({ error: "INVALID_SIGNATURE" }, 401);
    }
    const payload = JSON.parse(new TextDecoder().decode(raw));
    if (payload.object !== "whatsapp_business_account") {
      return json({ error: "INVALID_OBJECT" }, 400);
    }
    for (const entry of (payload.entry || []).slice(0, 20)) {
      for (const change of (entry.changes || []).slice(0, 20)) {
        const value = change.value;
        if (value?.metadata?.phone_number_id !== phoneId) continue;
        for (const message of (value.messages || []).slice(0, 20)) {
          if (message.type !== "text") continue; // Mídia/áudio requerem adaptador específico.
          const seconds = Number(message.timestamp);
          if (
            !Number.isFinite(seconds) || seconds * 1000 > Date.now() + 300000
          ) return json({ error: "INVALID_TIMESTAMP" }, 400);
          if (seconds * 1000 < Date.now() - 7 * 86400000) continue;
          const contact = (value.contacts || []).find((c: { wa_id: string }) =>
            c.wa_id === message.from
          );
          await ecoRpc("eco_ingest_whatsapp", {
            p_id: message.id,
            p_phone: message.from,
            p_text: message.text?.body,
            p_received: new Date(seconds * 1000).toISOString(),
            p_nome: contact?.profile?.name || "Cliente",
          });
        }
      }
    }
    kickWorker();
    return json({ ok: true });
  } catch (e) {
    return json({
      error: e instanceof RangeError ? "PAYLOAD_TOO_LARGE" : "RETRY_REQUIRED",
    }, e instanceof RangeError ? 413 : 503);
  }
});
