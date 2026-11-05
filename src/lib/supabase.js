import { createClient } from "@supabase/supabase-js";
import { oneRecord } from "./operations";
import { reportError } from "./monitoring";
import { fetchWithTimeout } from "./network";
const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
function publicKey(value) {
  if (!value || value.startsWith("sb_secret_")) return false;
  if (value.startsWith("sb_publishable_")) return true;
  try {
    return (
      JSON.parse(
        atob(value.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")),
      ).role === "anon"
    );
  } catch {
    return false;
  }
}
function validUrl(value) {
  try {
    const parsed = new URL(value);
    return (
      Boolean(parsed.hostname) &&
      (parsed.protocol === "https:" ||
        (parsed.protocol === "http:" &&
          ["localhost", "127.0.0.1"].includes(parsed.hostname)))
    );
  } catch {
    return false;
  }
}
export const configured = Boolean(validUrl(url) && publicKey(key));
export const supabase = configured
  ? createClient(url, key, {
      global: { fetch: fetchWithTimeout },
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false,
      },
      realtime: {
        params: { eventsPerSecond: 10 },
        heartbeatIntervalMs: 25000,
        reconnectAfterMs: (tries) => Math.min(1000 * 2 ** tries, 30000),
      },
    })
  : null;
export async function rpc(name, args) {
  if (!supabase) throw new Error("Configure o Supabase para continuar.");
  const { data, error } = await supabase.rpc(name, args);
  if (error) {
    const failure = new Error(
      error.code === "23505" && name === "confirm_manual_pix"
        ? "Esta referência bancária já foi utilizada. Confira o extrato e o pedido correto."
        : error.code === "23505" && name === "confirm_manual_pix_refund"
          ? "Esta referência de devolução já foi registrada. Confira a auditoria."
          : friendlyError(error.message),
    );
    failure.code = error.code;
    failure.conflict = error.message?.includes("idempotency_conflict");
    failure.rejected = /^(P0001|22[A-Z0-9]{3}|23[A-Z0-9]{3}|42501|40001)$/.test(
      error.code || "",
    );
    reportError(failure, `rpc:${name}`);
    throw failure;
  }
  return [
    "create_order",
    "begin_payment",
    "request_refund",
    "claim_external_order",
  ].includes(name)
    ? oneRecord(data)
    : data;
}
export function friendlyError(message = "") {
  const errors = {
    justification_required:
      "Informe uma justificativa entre 5 e 500 caracteres.",
    insufficient_cash:
      "Saldo físico insuficiente no caixa. Confira as vendas e os movimentos.",
    discount_not_allowed:
      "Desconto indisponível: confira se o pedido ainda está sem cobrança e se o valor é válido.",
    bank_reference_required:
      "Informe a referência real da transação no extrato bancário.",
    immutable_audit_log: "Os registros de auditoria são imutáveis.",
    checkout_rate_limit:
      "Muitos pedidos neste link. Aguarde um minuto e retome a mesma tentativa.",
    link_unavailable: "Link indisponível, expirado ou revogado.",
    last_admin: "O último administrador ativo não pode ser removido.",
    admin_open_shift_required:
      "Abra um caixa de administrador para devolver dinheiro.",
    no_confirmed_payment:
      "Não existe pagamento confirmado disponível para estorno.",
    access_denied: "Seu perfil não tem permissão ou o terminal está bloqueado.",
    open_shift_required: "Abra seu caixa antes de registrar pedidos.",
    pending_orders_in_shift:
      "Resolva os pedidos aguardando pagamento antes de fechar o caixa.",
    idempotency_conflict:
      "Esta tentativa já foi usada para outro pedido. Consulte o atendimento anterior.",
    payment_reconciliation_required:
      "Este pedido exige conciliação do pagamento antes de cancelar.",
    product_unavailable: "Um produto ficou indisponível. Atualize o cardápio.",
    invalid_modifier: "Uma observação não é permitida para este produto.",
    shift_unavailable: "Caixa indisponível ou já fechado.",
  };
  return (
    Object.entries(errors).find(([key]) => message.includes(key))?.[1] ||
    "Não foi possível concluir. Confira a conexão e tente novamente com a mesma tentativa."
  );
}
