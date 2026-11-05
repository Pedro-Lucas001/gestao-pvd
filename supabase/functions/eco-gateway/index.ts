import { readLimited } from "../_shared/http.ts";
import { bridgeSignature } from "../_shared/eco_validation.ts";
import { ecoRpc, json } from "../_shared/eco.ts";
Deno.serve(async (req: Request) => {
  if (!["GET", "POST"].includes(req.method)) {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }
  const url = new URL(req.url),
    source = req.headers.get("X-Integration-Source") || "";
  let keys: Record<string, string>;
  try {
    keys = JSON.parse(Deno.env.get("ECO_GATEWAY_KEYS") || "{}");
  } catch {
    return json({ error: "NOT_CONFIGURED" }, 503);
  }
  const secret = Object.hasOwn(keys, source) && typeof keys[source] === "string"
    ? keys[source]
    : "";
  if (!secret) return json({ error: "UNKNOWN_SOURCE" }, 401);
  try {
    const raw = await readLimited(req);
    if (
      !await bridgeSignature({
        method: req.method,
        path: url.pathname + url.search,
        source,
        timestamp: req.headers.get("X-Timestamp") || "",
        raw,
        signature: req.headers.get("X-Signature"),
        secret,
      })
    ) return json({ error: "INVALID_SIGNATURE" }, 401);
    const route = url.pathname.split("/").at(-1);
    if (req.method === "GET" && route === "events") {
      return json(await ecoRpc("eco_pull_events", { p_source: source }));
    }
    if (req.method !== "POST") return json({ error: "UNKNOWN_ROUTE" }, 404);
    const body = JSON.parse(new TextDecoder().decode(raw));
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json({ error: "INVALID_BODY" }, 400);
    }
    if (route === "orders") {
      return json({
        order_id: await ecoRpc("eco_ingest_order", {
          p_source: source,
          p_event_id: body.event_id,
          p_external_order_id: body.external_order_id,
          p_payload: body.order,
        }),
      }, 201);
    }
    if (route === "fulfillment") {
      await ecoRpc("eco_fulfillment", {
        p_source: source,
        p_event: body.event_id,
        p_order: body.order_id,
        p_status: body.status,
      });
      return json({ ok: true });
    }
    if (route === "ack") {
      await ecoRpc("eco_ack_event", { p_source: source, p_id: body.id });
      return json({ ok: true });
    }
    return json({ error: "UNKNOWN_ROUTE" }, 404);
  } catch (e) {
    return json({
      error: e instanceof RangeError ? "PAYLOAD_TOO_LARGE" : "EVENT_REJECTED",
    }, e instanceof RangeError ? 413 : 400);
  }
});
