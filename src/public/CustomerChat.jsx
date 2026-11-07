import { useState } from "react";
import { MessageCircle, Send, X } from "lucide-react";
import { Link } from "react-router-dom";
import { customerApi } from "./customerApi";
import { useCart, draftLine } from "./cart";

export default function CustomerChat({ shop, catalog = [] }) {
  const [consent, setConsent] = useState(false),
    [open, setOpen] = useState(false),
    [text, setText] = useState(""),
    [messages, setMessages] = useState([]),
    [busy, setBusy] = useState(false);
  const { setItems } = useCart();
  async function send(event) {
    event.preventDefault();
    if (!text.trim() || busy || !consent) return;
    const message = text.trim();
    setText("");
    setBusy(true);
    const history = messages
      .slice(-6)
      .map((m) => ({ role: m.role, content: m.text }));
    setMessages((p) => [...p.slice(-11), { role: "user", text: message }]);
    try {
      const result = await customerApi(
        "chat",
        { message, history, consent },
        undefined,
        "customer-assistant",
      );
      setMessages((p) => [
        ...p.slice(-11),
        {
          role: "assistant",
          text: result.reply,
          items: result.items,
          handoff: result.handoff,
        },
      ]);
    } catch {
      setMessages((p) => [
        ...p,
        {
          role: "assistant",
          text: "O assistente está indisponível. Monte seu pedido no cardápio ou fale com nossa equipe.",
          handoff: true,
        },
      ]);
    } finally {
      setBusy(false);
    }
  }
  function apply(suggestion) {
    const lines = suggestion
      .map((i) => {
        const p = catalog.find((p) => (p.product_id || p.id) === i.product_id);
        return p
          ? { ...draftLine(p, i.quantity), modifiers: i.modifiers, notes: "" }
          : null;
      })
      .filter(Boolean);
    if (lines.length === suggestion.length) {
      setItems(lines);
      setOpen(false);
    }
  }
  return (
    <div className="customer-chat">
      {!open ? (
        <button
          className="chat-launch"
          type="button"
          onClick={() => setOpen(true)}
        >
          <MessageCircle size={19} />
          Precisa de ajuda?
        </button>
      ) : (
        <section className="chat-panel" aria-label="Assistente virtual">
          <header>
            <div>
              <strong>Assistente do Planeta</strong>
              <small>
                Atendimento virtual · confirme seu pedido no checkout
              </small>
            </div>
            <button
              type="button"
              aria-label="Fechar atendimento"
              onClick={() => setOpen(false)}
            >
              <X size={18} />
            </button>
          </header>
          <p className="chat-privacy">
            Não envie senhas, documentos ou dados de cartão. As mensagens podem
            ser processadas pela OpenAI para responder ao atendimento.
          </p>
          <div className="chat-messages" aria-live="polite">
            {!messages.length && (
              <p>
                Olá! Posso ajudar a escolher seu lanche e explicar pedidos,
                pagamentos e entrega. Para falar com uma pessoa, escreva HUMANO.
              </p>
            )}
            {messages.map((m, n) => (
              <article key={n} className={`chat-message ${m.role}`}>
                <p>{m.text}</p>
                {m.items?.length > 0 && catalog.length > 0 && (
                  <>
                    <button type="button" onClick={() => apply(m.items)}>
                      Usar sugestão no carrinho
                    </button>
                    <small>
                      Substitui os itens atuais; você revisa antes de confirmar.
                    </small>
                    <Link to="/pedido" onClick={() => apply(m.items)}>
                      Revisar pedido →
                    </Link>
                  </>
                )}
                {m.handoff && shop?.whatsapp_number && (
                  <a
                    href={`https://wa.me/${shop.whatsapp_number}`}
                    target="_blank"
                    rel="noreferrer"
                  >
                    Falar com a equipe no WhatsApp
                  </a>
                )}
              </article>
            ))}
            {busy && <p role="status">Consultando o cardápio…</p>}
          </div>
          <label className="chat-consent">
            <input
              type="checkbox"
              checked={consent}
              disabled={busy}
              onChange={(e) => setConsent(e.target.checked)}
            />
            Autorizo o uso das mensagens desta conversa pela IA da OpenAI para
            este atendimento.
          </label>
          <form onSubmit={send}>
            <label className="sr-only" htmlFor="chat-message">
              Sua mensagem
            </label>
            <input
              id="chat-message"
              value={text}
              maxLength={1000}
              onChange={(e) => setText(e.target.value)}
              placeholder="Ex.: quero 2 dogs sem cebola"
            />
            <button
              type="submit"
              disabled={busy || !consent || !text.trim()}
              aria-label="Enviar mensagem"
            >
              <Send size={17} />
            </button>
          </form>
        </section>
      )}
    </div>
  );
}
