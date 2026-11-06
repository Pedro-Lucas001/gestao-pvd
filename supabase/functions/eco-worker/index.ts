import { MetaClient, sameSecret } from "../_shared/meta.ts";
import { EcoRejected, ecoRpc, json } from "../_shared/eco.ts";
import { command } from "../_shared/eco_validation.ts";
import { currency, salesReply } from "../_shared/eco_ai.ts";
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  if (
    !await sameSecret(
      req.headers.get("X-Worker-Secret") || "",
      Deno.env.get("ECO_WORKER_SECRET") || "",
    )
  ) return json({ error: "DENIED" }, 401);
  const token = Deno.env.get("WHATSAPP_ACCESS_TOKEN"),
    phoneId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  if (!token || !phoneId) return json({ error: "META_NOT_CONFIGURED" }, 503);
  let messenger: MetaClient;
  try {
    messenger = new MetaClient(
      token,
      phoneId,
      Deno.env.get("WHATSAPP_GRAPH_VERSION") || "v23.0",
    );
  } catch {
    return json({ error: "META_NOT_CONFIGURED" }, 503);
  }
  let messages = 0, campaigns = 0;
  try {
    await ecoRpc("eco_cleanup");
    const job = await ecoRpc<
      | { id: string; lease_token: string; texto: string; telefone: string }
      | null
    >("eco_claim_whatsapp");
    if (job) {
      let reply = "", outbound: string | null = null;
      try {
        const action = command(job.texto);
        if (action === "privacy") {
          const portal = new URL(Deno.env.get("ECO_PRIVACY_PORTAL_URL") || "");
          if (portal.protocol !== "https:" || portal.search || portal.hash) {
            throw new Error("PORTAL_NOT_CONFIGURED");
          }
          portal.hash = `token=${await ecoRpc<string>("eco_privacy_link", {
            p_id: job.id,
            p_lease: job.lease_token,
          })}`;
          reply =
            `Acesse seus dados ou solicite exclusão neste link pessoal, válido por 15 minutos: ${portal}\nNão compartilhe o link. Compras e comprovantes mínimos podem ser retidos para obrigações legais; contato e conversas serão apagados. Enquanto houver pedido ativo, a exclusão será concluída ao encerrá-lo.`;
        } else if (action === "confirm") {
          const sale = await ecoRpc<{ order_id: string; total: number }>(
            "eco_ai_confirm",
            { p_id: job.id, p_lease: job.lease_token },
          );
          reply = `Pedido ${sale.order_id} registrado. Total dos produtos: ${
            currency(Number(sale.total))
          }. A equipe precisa confirmar o recebimento antes de enviar à cozinha. Informe-se com a equipe sobre Pix, retirada ou entrega.`;
        } else if (action === "optout") {
          reply =
            "Você não receberá novas campanhas. Mensagens que já estavam sendo transmitidas podem chegar. O atendimento de pedidos continua disponível.";
        } else if (action === "optin") {
          reply =
            "Você autorizou promoções do Planeta Lanches pelo WhatsApp. Pode revogar a qualquer momento enviando SAIR. Não é necessário autorizar para comprar.";
        } else if (action === "human") {
          await ecoRpc("eco_handoff", {
            p_id: job.id,
            p_lease: job.lease_token,
          });
          reply =
            "Seu atendimento foi encaminhado à equipe. Aguarde o retorno; não envie senhas ou dados de cartão.";
        } else {
          try {
            reply = await salesReply(job);
          } catch {
            await ecoRpc("eco_handoff", {
              p_id: job.id,
              p_lease: job.lease_token,
            });
            reply =
              "O atendimento automático está indisponível. Sua mensagem foi encaminhada à equipe, que vai conferir produtos, valores e entrega com você.";
          }
        }
        outbound = await messenger.text(job.telefone, reply);
        await ecoRpc("eco_finish_whatsapp", {
          p_id: job.id,
          p_lease: job.lease_token,
          p_reply: reply,
          p_outbound_id: outbound,
          p_success: true,
        });
        messages++;
      } catch (e) {
        if (
          !outbound && e instanceof EcoRejected && /^(P0001|22|23)/.test(e.code)
        ) {
          await ecoRpc("eco_handoff", {
            p_id: job.id,
            p_lease: job.lease_token,
          });
          reply =
            "A equipe precisa conferir seu pedido: pode haver alteração no cardápio, indisponibilidade de estoque ou resumo expirado. Não repita o pagamento. Sua mensagem foi encaminhada ao atendimento.";
          outbound = await messenger.text(job.telefone, reply);
          await ecoRpc("eco_finish_whatsapp", {
            p_id: job.id,
            p_lease: job.lease_token,
            p_reply: reply,
            p_outbound_id: outbound,
            p_success: true,
          });
          messages++;
        }
        // Sem detalhes de erro, conversa ou telefone nos logs. Retry limitado e idempotência no banco.
        if (!outbound) {
          await ecoRpc("eco_finish_whatsapp", {
            p_id: job.id,
            p_lease: job.lease_token,
            p_reply: "",
            p_outbound_id: null,
            p_success: false,
          });
        }
      }
    }
    const campaign = await ecoRpc<
      {
        id: string;
        lease_token: string;
        telefone: string;
        template_name: string;
        template_language: string;
      } | null
    >("eco_claim_campaign");
    if (campaign) {
      let outbound: string | null = null;
      try {
        if (
          await ecoRpc<boolean>("eco_campaign_allowed", {
            p_id: campaign.id,
            p_lease: campaign.lease_token,
          })
        ) {
          outbound = await messenger.send(campaign.telefone, {
            type: "template",
            template: {
              name: campaign.template_name,
              language: { code: campaign.template_language },
            },
          });
          campaigns++;
        }
      } finally {
        await ecoRpc("eco_finish_campaign", {
          p_id: campaign.id,
          p_lease: campaign.lease_token,
          p_outbound: outbound,
          p_success: Boolean(outbound),
        });
      }
    }
    return json({ ok: true, messages, campaigns });
  } catch {
    return json({ error: "WORKER_RETRY_REQUIRED" }, 503);
  }
});
