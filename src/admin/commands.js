import { rpc, supabase } from "../lib/supabase";
export async function command(name, body) {
  const user = (await supabase.auth.getSession()).data.session?.user.id;
  if (!user) throw new Error("Entre novamente para continuar.");
  const slot = `planeta:command:${user}:${name}`;
  let saved;
  try {
    saved = JSON.parse(sessionStorage.getItem(slot) || "null");
  } catch {
    throw new Error(
      "Armazenamento do terminal indisponível. Não foi enviada nenhuma operação.",
    );
  }
  const serialized = JSON.stringify(body);
  if (saved && saved.body !== serialized)
    throw new Error(
      "Há uma tentativa pendente. Retome os mesmos valores ou confira a auditoria antes de iniciar outra operação.",
    );
  const record = saved || { key: crypto.randomUUID(), body: serialized };
  sessionStorage.setItem(slot, JSON.stringify(record));
  try {
    const result = await rpc(name, { ...body, p_key: record.key });
    sessionStorage.removeItem(slot);
    return result;
  } catch (error) {
    if (error.rejected && error.code !== "42501" && !error.conflict)
      sessionStorage.removeItem(slot);
    throw error;
  }
}
export async function invoke(name, body) {
  const { data, error } = await supabase.functions.invoke(name, { body });
  if (error) {
    let message =
      "A integração não pôde confirmar a operação. Não repita um envio externo antes de conferir seu estado.";
    try {
      const payload = await error.context.json();
      const known = {
        WHATSAPP_API_NOT_CONFIGURED:
          "A API oficial do WhatsApp ainda não foi configurada.",
        CONVERSATION_WINDOW_EXPIRED_USE_APPROVED_TEMPLATE:
          "A janela de resposta terminou. Use um modelo aprovado do WhatsApp.",
        USER_CREATION_FAILED_CHECK_EXISTING_EMAIL:
          "Não foi possível criar a conta. Confira se o e-mail já foi cadastrado.",
        ACCOUNT_CREATED_INACTIVE_FINISH_IN_TEAM:
          "Conta criada, ainda inativa. Conclua a ativação em Equipe e acessos.",
        ACCOUNT_CREATED_SET_PIN_IN_TEAM:
          "Conta criada. Configure o PIN em Equipe e acessos.",
        SEND_UNCONFIRMED_CHECK_CONVERSATION_BEFORE_RETRY:
          "Envio não confirmado. Confira a conversa antes de reenviar para evitar duplicação.",
        SENT_AUDIT_UNCONFIRMED_DO_NOT_RESEND:
          "A mensagem foi enviada, mas a auditoria não foi confirmada. Não reenvie; avise a administração.",
        AUTH_REQUIRED: "Entre novamente para continuar.",
        ADMIN_REQUIRED: "Somente administradores podem realizar esta ação.",
      };
      message =
        known[payload.error] ||
        (/^[A-Z0-9_]+$/.test(payload.error || "")
          ? "O serviço não pôde concluir esta operação. Confira a configuração e tente novamente."
          : payload.error) ||
        message;
    } catch {
      /* Preserve uncertainty. */
    }
    throw new Error(message);
  }
  return data;
}
export function reason(form) {
  return String(form.get("reason") || "").trim();
}
