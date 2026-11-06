import { createClient } from "npm:@supabase/supabase-js@2.99.0";
import { response } from "../_shared/http.ts";
import { sameSecret, MetaClient, faq } from "../_shared/meta.ts";
const labels: Record<string, string> = {
  "order.cancelled":
    "cancelado; se já pagou, fale com a loja para conferência e devolução",
  "order.paid": "pagamento confirmado e enviado à cozinha",
  "order.ready": "pronto",
  "order.dispatched": "saiu para entrega",
  "order.delivered": "entregue",
  "order.refunded": "estorno registrado",
};
Deno.serve(async (req: Request) => {
  if (req.method !== "POST")
    return response({ error: "METHOD_NOT_ALLOWED" }, 405);
  if (
    !(await sameSecret(
      req.headers.get("X-Worker-Secret") || "",
      Deno.env.get("INTEGRATION_WORKER_SECRET") || "",
    ))
  )
    return response({ error: "ACCESS_DENIED" }, 401);
  const token = Deno.env.get("WHATSAPP_ACCESS_TOKEN"),
    phone = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  if (!token || !phone)
    return response({ error: "WHATSAPP_NOT_CONFIGURED_NO_JOBS_CLAIMED" }, 503);
  const meta = new MetaClient(
    token,
    phone,
    Deno.env.get("WHATSAPP_GRAPH_VERSION") || "v23.0",
  );
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  const { data: jobs, error } = await db.rpc("claim_notifications", {
    p_limit: 10,
  });
  if (error) return response({ error: "QUEUE_UNAVAILABLE" }, 503);
  let sent = 0,
    retry = 0;
  for (const job of jobs || []) {
    let success = false,
      code: string | null = null;
    try {
      const status = labels[job.topic];
      if (!status) throw new Error("UNSUPPORTED_TOPIC");
      const recipient = job.phone.replace(/\D/g, "");
      if (job.within_window)
        await meta.text(
          recipient,
          `Planeta Lanches · Pedido #${job.order_number}: ${status}.`,
        );
      else {
        const template = Deno.env.get("WHATSAPP_STATUS_TEMPLATE");
        if (!template) throw new Error("APPROVED_TEMPLATE_REQUIRED");
        await meta.status(
          recipient,
          template,
          Deno.env.get("WHATSAPP_TEMPLATE_LANGUAGE") || "pt_BR",
          String(job.order_number),
          status,
        );
      }
      success = true;
      sent++;
    } catch (e) {
      code = e instanceof Error ? e.message : "SEND_FAILED";
      retry++;
    }
    const { error } = await db.rpc("finish_notification", {
      p_id: job.id,
      p_success: success,
      p_error: code,
    });
    if (error) return response({ error: "ACK_UNCONFIRMED" }, 503);
  }
  const { data: replies, error: claimError } = await db.rpc(
    "claim_message_replies",
  );
  if (claimError) return response({ error: "REPLY_QUEUE_UNAVAILABLE" }, 503);
  for (const job of replies || []) {
    let success = false;
    try {
      if (new Date(job.received_at).getTime() < Date.now() - 23 * 3600000)
        throw new Error("CONVERSATION_WINDOW_EXPIRED");
      await meta.text(
        job.sender,
        faq(job.body, Deno.env.get("WHATSAPP_MENU_URL") || ""),
      );
      success = true;
      sent++;
    } catch {
      retry++;
    }
    const { error } = await db.rpc("finish_message_reply", {
      p_id: job.id,
      p_success: success,
    });
    if (error) return response({ error: "ACK_UNCONFIRMED" }, 503);
  }
  return response({ sent, retry });
});
