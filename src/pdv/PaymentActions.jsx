import {
  ArrowRight,
  Banknote,
  Check,
  Clock3,
  CreditCard,
  LockKeyhole,
  Plus,
  RotateCcw,
  Smartphone,
} from "lucide-react";
import { QRCodeSVG } from "qrcode.react";
import { operationUI as ui } from "../design/operational";
export default function PaymentActions(
  {
    draft,
    busy,
    online,
    preview,
    method,
    setMethod,
    paymentIntent,
    pay,
    send,
    reset,
    cancelUnpaid,
    error,
  },
) {
  return (
    <>
      {draft.order?.status === "cancelled"
        ? (
          <div className="error-message">
            <h3>Pedido cancelado.</h3>
            <p>Este pedido não está disponível para pagamento.</p>
            <button className={ui.secondary} onClick={reset}>
              Novo pedido
            </button>
          </div>
        )
        : draft.payment?.status === "confirmed"
        ? (
          <div className="payment-success" role="status">
            <Check size={23} />
            <h3>Pagamento confirmado.</h3>
            <p>Pedido liberado para os setores da cozinha.</p>
            <button className={`${ui.action} pl:w-full`} onClick={reset}>
              Começar próximo pedido
              <Plus size={16} />
            </button>
          </div>
        )
        : draft.order
        ? (
          <>
            <div className="payment-options">
              {[
                ["cash", "Dinheiro", Banknote],
                ["pix", "Pix", Smartphone],
                ["tef", "Cartão", CreditCard],
              ].map(([id, label, Icon]) => (
                <button
                  key={id}
                  disabled={busy || Boolean(draft.payment)}
                  className={method === id ? "active" : ""}
                  onClick={() => setMethod(id)}
                >
                  <Icon size={17} />
                  {label}
                </button>
              ))}
            </div>
            {method !== "cash" && (
              <p className="payment-disclaimer">
                Pix Nubank de conta física: confirmação manual do administrador.
                TEF exige serviço homologado.
              </p>
            )}
            {paymentIntent?.pix && (
              <div className="pix-code">
                <QRCodeSVG
                  value={paymentIntent.pix.copyPaste}
                  size={150}
                />
                <p>
                  {paymentIntent.pix.expiresAt
                    ? `Válido até ${
                      new Date(paymentIntent.pix.expiresAt)
                        .toLocaleTimeString("pt-BR")
                    }`
                    : "QR Pix estático, sem expiração automática. Aguarde a conferência do crédito pelo administrador."}
                </p>
                <button
                  className={ui.secondary}
                  onClick={() =>
                    navigator.clipboard.writeText(
                      paymentIntent.pix.copyPaste,
                    )}
                >
                  Copiar código Pix
                </button>
                <code>{paymentIntent.pix.copyPaste}</code>
              </div>
            )}
            <button
              className={`${ui.action} pl:w-full`}
              disabled={!online || busy || preview}
              onClick={pay}
            >
              {busy
                ? "Processando…"
                : draft.payment
                ? "Retomar mesma tentativa"
                : method === "cash"
                ? "Confirmar recebimento em dinheiro"
                : method === "pix"
                ? "Gerar Pix com valor do pedido"
                : "Iniciar TEF"}
              <ArrowRight size={17} />
            </button>
            <p className="field-note">
              <LockKeyhole size={12} />A cozinha só recebe após a confirmação
              válida.
            </p>
          </>
        )
        : (
          <>
            <button
              className={`${ui.action} pl:w-full`}
              onClick={send}
              disabled={!draft.items.length || busy || !online || preview}
            >
              {busy
                ? "Enviando…"
                : draft.submitted
                ? "Reenviar mesma tentativa"
                : "Cobrar e Enviar (KDS)"}
              {draft.submitted
                ? <RotateCcw size={17} />
                : <ArrowRight size={17} />}
            </button>
            <p className="field-note">
              <Clock3 size={12} />
              {preview
                ? "Prévia sem banco. Pagamentos e envios desativados."
                : "A cozinha recebe o pedido após a confirmação do pagamento."}
            </p>
          </>
        )}
      {draft.order?.status === "pending_payment" && !draft.payment && (
        <button
          className="pl:mt-3 pl:w-full pl:rounded-lg pl:border-0 pl:bg-transparent pl:px-3 pl:py-2 pl:text-xs pl:text-gray-400 pl:transition-colors pl:hover:text-[#ff5722]"
          disabled={busy || !online}
          onClick={cancelUnpaid}
        >
          Cancelar pedido ainda sem cobrança
        </button>
      )}
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
      {draft.items.length > 0 && !draft.order && !draft.submitted && (
        <button
          className="pl:mt-3 pl:w-full pl:rounded-lg pl:border-0 pl:bg-transparent pl:px-3 pl:py-2 pl:text-xs pl:text-gray-400 pl:transition-colors pl:hover:text-[#ff5722]"
          disabled={busy}
          onClick={() => {
            if (confirm("Limpar o pedido em rascunho?")) reset();
          }}
        >
          Limpar rascunho
        </button>
      )}
    </>
  );
}
