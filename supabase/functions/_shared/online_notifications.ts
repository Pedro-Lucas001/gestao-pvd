import { MetaClient } from "./meta.ts";
import { onlineRpc, publicSite } from "./online.ts";
import { ensureOnlineIntent, type OnlinePayment } from "./online_payments.ts";
import { staticPixKey } from "./pix.ts";
type OnlineJob = {
  id: string;
  topic: string;
  number: number;
  due_cents: number;
  phone: string;
  within_window: boolean;
  payment: OnlinePayment | null;
  tracking: string | null;
};
const labels: Record<string, string> = {
  "order.received": "recebido; acompanhe a confirmação e o pagamento no site",
  "order.paid": "pagamento confirmado; pedido liberado à cozinha",
  "order.cash_accepted":
    "aceito para preparo; consulte o recebimento no acompanhamento",
  "order.delivery_accepted":
    "enviado à cozinha; acompanhe as etapas e o pagamento no site",
  "order.payment_requested": "Pix pendente",
  "order.preparing": "em preparo",
  "order.ready": "pronto",
  "order.dispatched": "saiu para entrega",
  "order.completed": "concluído",
  "change.accepted": "alteração aceita pela cozinha",
};
export async function sendOnlineNotifications(
  meta: MetaClient,
): Promise<{ sent: number; retry: number }> {
  const jobs = await onlineRpc<OnlineJob[]>("online_claim_notifications");
  let sent = 0,
    retry = 0;
  for (const job of jobs) {
    let success = false,
      code: string | null = null;
    try {
      const label =
        job.topic === "order.payment_requested" && job.due_cents <= 0
          ? "sem saldo pendente; consulte o acompanhamento"
          : job.topic.startsWith("change.rejected:")
            ? "solicitação de alteração não aceita; consulte o acompanhamento"
            : labels[job.topic];
      if (!label) throw new Error("UNKNOWN_ONLINE_NOTIFICATION");
      const amount = (job.due_cents / 100).toLocaleString("pt-BR", {
        style: "currency",
        currency: "BRL",
      });
      const pix = job.payment
        ? (await ensureOnlineIntent(job.payment)).pix
        : null;
      if (job.payment && !pix) throw new Error("PIX_NOT_AVAILABLE");
      const key = pix ? staticPixKey(pix) : null;
      const link =
        job.tracking && /^[a-f0-9]{64}$/.test(job.tracking)
          ? `${publicSite()}/pedido#acompanhar=${job.tracking}`
          : null;
      if (job.within_window) {
        await meta.text(
          job.phone,
          `Planeta Lanches · Pedido #${job.number}: ${label}.${pix ? `\nPagamento pendente: ${amount}.${key ? `\nChave Pix: ${key}` : ""}\nPix copia e cola:\n${pix}\nO recebimento será confirmado pela loja ou pelo provedor.` : ""}${link ? `\nAcompanhe seu pedido: ${link}` : ""}`,
        );
      } else if (pix) {
        const template = Deno.env.get("WHATSAPP_ONLINE_PAYMENT_TEMPLATE");
        if (!template) throw new Error("APPROVED_PAYMENT_TEMPLATE_REQUIRED");
        await meta.template(
          job.phone,
          template,
          Deno.env.get("WHATSAPP_TEMPLATE_LANGUAGE") || "pt_BR",
          [
            String(job.number),
            amount,
            key ? `Chave Pix: ${key} · Copia e cola: ${pix}` : pix,
          ],
        );
      } else {
        const template = Deno.env.get("WHATSAPP_ONLINE_STATUS_TEMPLATE");
        if (!template) throw new Error("APPROVED_STATUS_TEMPLATE_REQUIRED");
        await meta.status(
          job.phone,
          template,
          Deno.env.get("WHATSAPP_TEMPLATE_LANGUAGE") || "pt_BR",
          String(job.number),
          `${label}${link ? ` · Acompanhe: ${link}` : ""}`,
        );
      }
      success = true;
      sent++;
    } catch (error) {
      code = error instanceof Error ? error.message : "SEND_FAILED";
      retry++;
    }
    await onlineRpc("online_finish_notification", {
      p_id: job.id,
      p_success: success,
      p_error: code,
    });
  }
  return { sent, retry };
}
