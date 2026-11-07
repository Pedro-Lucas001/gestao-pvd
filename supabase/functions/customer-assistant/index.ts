import { cors, readLimited, response } from "../_shared/http.ts";
import { customerRate } from "../_shared/online.ts";
import { customerAssistant } from "../_shared/customer_assistant.ts";
Deno.serve(async (req: Request) => {
  const headers = cors(req);
  if (!headers) return response({ error: "Origem não autorizada." }, 403);
  const reply = (value: unknown, status = 200) => {
    const r = response(value, status);
    for (const [k, v] of Object.entries(headers)) r.headers.set(k, v);
    return r;
  };
  if (req.method === "OPTIONS") return reply({ ok: true });
  if (req.method !== "POST")
    return reply({ error: "Método não permitido." }, 405);
  try {
    await customerRate(req, "assistant", 10, 3600);
    const { message, history, consent } = JSON.parse(
      new TextDecoder().decode(await readLimited(req, 8192)),
    );
    if (
      typeof message !== "string" ||
      !message.trim() ||
      message.length > 2000 ||
      (history && (!Array.isArray(history) || history.length > 6))
    )
      return reply({ error: "Mensagem inválida." }, 400);
    return reply(
      await customerAssistant(message, history || [], consent === true),
    );
  } catch {
    return reply({
      reply:
        "O atendimento automático está indisponível agora. Consulte o cardápio ou fale com nossa equipe.",
      handoff: true,
      items: [],
      subtotal_cents: 0,
      automated: false,
    });
  }
});
