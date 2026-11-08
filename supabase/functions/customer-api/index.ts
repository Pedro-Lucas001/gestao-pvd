import { cors, readLimited, response } from "../_shared/http.ts";
import { customerRate, onlineRpc } from "../_shared/online.ts";
import {
  ensureOnlineIntent,
  paymentCapabilities,
  type OnlinePayment,
} from "../_shared/online_payments.ts";

const messages: Record<string, string> = {
  invalid_contact: "Confira seu nome e WhatsApp com DDD.",
  payment_unavailable: "Forma de pagamento indisponível.",
  shop_closed: "Os pedidos online estão pausados.",
  delivery_unavailable: "Entrega indisponível. Selecione retirada.",
  price_changed_review_order: "Os valores mudaram. Confira o resumo novamente.",
  invalid_change_amount: "O valor para troco precisa cobrir o total do pedido.",
  delivery_contact_required: "Informe o endereço completo para entrega.",
  delivery_reference_required: "Informe um ponto de referência para a entrega.",
  email_required: "Informe um e-mail válido para o pagamento.",
  change_not_allowed:
    "O pedido não pode ser alterado nesta etapa ou tem uma cobrança em aberto. Fale com a equipe.",
  product_unavailable: "Um produto ficou indisponível. Confira o carrinho.",
  invalid_modifier: "Uma personalização não está disponível para esse item.",
  idempotency_conflict:
    "Esta tentativa já foi usada com outros dados. Consulte seu pedido antes de tentar novamente.",
  order_unavailable:
    "Pedido não encontrado. Use seu link privado de acompanhamento.",
  RATE_LIMIT: "Muitas tentativas. Aguarde um pouco e tente novamente.",
  CARD_CREATION_REQUIRES_RECONCILIATION:
    "A criação do checkout precisa ser conferida pela equipe. Não repita o pagamento.",
};
Deno.serve(async (req: Request) => {
  const headers = cors(req);
  if (!headers) return response({ error: "Origem não autorizada." }, 403);
  const reply = (data: unknown, status = 200) => {
    const r = response(data, status);
    for (const [k, v] of Object.entries(headers)) r.headers.set(k, v);
    return r;
  };
  if (req.method === "OPTIONS") return reply({ ok: true });
  if (req.method !== "POST")
    return reply({ error: "Método não permitido." }, 405);
  try {
    const body = JSON.parse(
      new TextDecoder().decode(await readLimited(req, 32768)),
    );
    if (
      !body ||
      !["config", "quote", "create", "status", "change", "payment"].includes(
        body.action,
      )
    )
      return reply({ error: "Solicitação inválida." }, 400);
    await customerRate(
      req,
      `customer:${body.action}`,
      body.action === "create" ? 10 : 180,
      60,
    );
    if (body.action === "config") {
      const c = await onlineRpc<{
        settings: Record<string, unknown>;
        products: unknown[];
      }>("online_assistant_catalog");
      return reply({
        ...c.settings,
        catalog: c.products,
        payments: paymentCapabilities(),
      });
    }
    if (body.action === "quote")
      return reply(
        body.tracking
          ? await onlineRpc("online_change_quote", {
              p_tracking: body.tracking,
              p_items: body.items,
            })
          : await onlineRpc("online_delivery_quote", {
              p_items: body.items,
              p_fulfillment: body.fulfillment,
              p_method: body.method || "pix",
            }),
      );
    if (body.action === "create") {
      const methods = paymentCapabilities();
      if (
        (body.method === "pix" && !methods.pix) ||
        (body.method === "card" && !methods.card)
      )
        return reply(
          {
            code: "payment_unavailable",
            error: "Esta forma de pagamento ainda não está disponível.",
          },
          409,
        );
      return reply(
        await onlineRpc("online_create_order", {
          p_key: body.key,
          p_tracking: body.tracking,
          p_items: body.items,
          p_contact: body.contact,
          p_fulfillment: body.fulfillment,
          p_method: body.method,
          p_change_for: body.change_for_cents ?? null,
          p_expected_total: body.expected_total_cents,
        }),
      );
    }
    if (body.action === "status")
      return reply(
        await onlineRpc("online_order_status", { p_tracking: body.tracking }),
      );
    if (body.action === "change")
      return reply({
        id: await onlineRpc("online_request_change", {
          p_tracking: body.tracking,
          p_key: body.key,
          p_items: body.items,
          p_reason: body.reason,
          p_expected_total: body.expected_total_cents,
        }),
      });
    if (body.action === "payment") {
      const payment = await onlineRpc<OnlinePayment>("online_prepare_payment", {
        p_tracking: body.tracking,
        p_key: body.key,
      });
      const artifact = await ensureOnlineIntent(payment);
      return reply({
        id: payment.id,
        amount_cents: payment.amount_cents,
        method: payment.method,
        ...artifact,
      });
    }
    return reply({ error: "Solicitação inválida." }, 400);
  } catch (error) {
    const code = error instanceof Error ? error.message : "FAILED";
    return reply(
      {
        code: messages[code] ? code : "FAILED",
        error:
          messages[code] ||
          (error instanceof RangeError
            ? "Solicitação muito grande."
            : "Não foi possível concluir. Confira a conexão e retome a mesma tentativa."),
      },
      code === "RATE_LIMIT" ? 429 : 409,
    );
  }
});
