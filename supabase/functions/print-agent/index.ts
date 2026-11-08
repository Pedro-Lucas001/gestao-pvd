import { readLimited, response } from "../_shared/http.ts";
import { customerRate, onlineRpc } from "../_shared/online.ts";

// This endpoint accepts only a printer-scoped credential, never a customer or
// employee token. It cannot register printers, change orders or confirm money.
Deno.serve(async (req: Request) => {
  if (req.method !== "POST" || req.headers.has("origin"))
    return response({ error: "METHOD_NOT_ALLOWED" }, 405);
  try {
    await customerRate(req, "print-agent", 60, 60);
    const body = JSON.parse(new TextDecoder().decode(await readLimited(req, 4096)));
    const token = req.headers.get("x-print-token");
    if (!token || !/^[a-f0-9]{64}$/.test(token))
      return response({ error: "ACCESS_DENIED" }, 401);
    if (body.action === "claim")
      return response(await onlineRpc("online_print_claim", { p_token: token }));
    if (body.action === "finish" && typeof body.success === "boolean") {
      await onlineRpc("online_print_finish", {
        p_token: token, p_id: body.id, p_claim: body.claim, p_success: body.success,
      });
      return response({ ok: true });
    }
    return response({ error: "INVALID_ACTION" }, 400);
  } catch (error) {
    const code = error instanceof Error ? error.message : "FAILED";
    return response({ error: code === "access_denied" ? "ACCESS_DENIED" : "PRINT_REQUEST_FAILED" }, code === "access_denied" ? 401 : 409);
  }
});
