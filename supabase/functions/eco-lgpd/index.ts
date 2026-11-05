import { cors } from "../_shared/http.ts";
import { bodyJson, ecoRpc, json } from "../_shared/eco.ts";
Deno.serve(async (req: Request) => {
  const headers = cors(req);
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: headers ? 204 : 403,
      headers: headers || {},
    });
  }
  if (req.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405, headers || {});
  }
  if (req.headers.has("Origin") && !headers) {
    return json({ error: "ORIGIN_DENIED" }, 403);
  }
  try {
    const body = await bodyJson(req);
    if (
      typeof body.token !== "string" || !/^[a-f0-9]{64}$/.test(body.token) ||
      !["acesso", "anonimizacao", "consentir_anuncios", "revogar_anuncios"]
        .includes(String(body.acao))
    ) return json({ error: "INVALID_REQUEST" }, 400, headers || {});
    return json(
      await ecoRpc("eco_privacy_request", {
        p_token: body.token,
        p_acao: body.acao,
      }),
      200,
      headers || {},
    );
  } catch (e) {
    return json(
      {
        error: e instanceof RangeError
          ? "PAYLOAD_TOO_LARGE"
          : "LINK_INVALID_OR_OPERATION_UNAVAILABLE",
      },
      e instanceof RangeError ? 413 : 403,
      headers || {},
    );
  }
});
