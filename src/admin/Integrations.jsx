import { useState, useEffect } from "react";
import { supabase, rpc } from "../lib/supabase";
import { invoke } from "./commands";
export default function Integrations() {
  const [status, setStatus] = useState(null),
    [jobs, setJobs] = useState([]),
    [error, setError] = useState("");
  async function load() {
    setError("");
    try {
      setStatus(await invoke("integration-status", {}));
    } catch {
      setStatus(null);
      setError(
        "Não foi possível verificar a configuração das Edge Functions. Publique/configure as funções no projeto Supabase.",
      );
    }
    const { data } = await supabase
      .from("integration_outbox")
      .select(
        "id,topic,order_id,attempts,last_error,next_attempt_at,delivered_at",
      )
      .order("next_attempt_at")
      .limit(100);
    setJobs(data || []);
  }
  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, []);
  return (
    <section className="management">
      <span className="eyebrow">INTEGRAÇÕES E RESILIÊNCIA</span>
      <h1>Conexões da operação.</h1>
      <p>
        Configuração presente não significa credencial válida ou homologação
        concluída. A confirmação automática de Pix/TEF não está disponível para
        a chave Pix da conta Nubank física.
      </p>
      <button className="secondary" onClick={load}>
        Verificar configuração
      </button>
      {error && (
        <p role="alert" className="error-message">
          {error}
        </p>
      )}
      <div className="management-grid">
        <article className="management-panel">
          <h2>Pix Nubank · conferência manual</h2>
          <p>
            {status?.pixConfigured
              ? "Variáveis do QR presentes no servidor. Valide a chave, o recebedor e o fluxo antes de operar."
              : "Cadastre PIX_KEY, PIX_MERCHANT_NAME, PIX_MERCHANT_CITY e PAYMENT_MODE=manual_pix nos segredos das funções."}
          </p>
          <p>
            QR com valor exato. Somente administrador confirma crédito ou
            registra devolução feita no app. Não existe acesso ao saldo ou senha
            bancária.
          </p>
        </article>
        <article className="management-panel">
          <h2>WhatsApp · API oficial</h2>
          <p>
            {status?.whatsappConfigured
              ? "Variáveis da API presentes; confirme assinatura, permissões, número, templates e envio em staging."
              : "O aplicativo Business não habilita a API automaticamente. Configure a conta da API oficial da Meta e seus segredos."}
          </p>
          <p>
            Webhook assinado, FAQ, caixa de entrada, mensagens por status e fila
            de retry. Mensagens fora da janela exigem template aprovado e
            consentimento.
          </p>
        </article>
        <article className="management-panel">
          <h2>TEF</h2>
          <p>
            Marca/modelo e serviço homologado ainda não informados. Pagamento
            TEF permanece indisponível; não há aprovação simulada.
          </p>
        </article>
        <article className="management-panel">
          <h2>Processador da fila</h2>
          <p>
            {status?.workerConfigured
              ? "Segredo do worker presente. Configure um agendamento autenticado para chamar integration-worker."
              : "Configure INTEGRATION_WORKER_SECRET e o agendamento no projeto."}
          </p>
          <p>
            Retentativas com backoff e lease. Após oito falhas, a administração
            deve conferir o motivo e autorizar novo ciclo.
          </p>
        </article>
      </div>
      <article className="management-panel">
        <h2>Eventos de notificação</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Evento</th>
                <th>Tentativas</th>
                <th>Estado</th>
                <th>Próxima tentativa</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {jobs.map((j) => (
                <tr key={j.id}>
                  <td>{j.topic}</td>
                  <td>{j.attempts}</td>
                  <td>
                    {j.delivered_at
                      ? "Confirmado pelo serviço"
                      : j.last_error || "Aguardando"}
                  </td>
                  <td>{new Date(j.next_attempt_at).toLocaleString("pt-BR")}</td>
                  <td>
                    {!j.delivered_at && (
                      <button
                        className="text-button"
                        onClick={async () => {
                          const reason = prompt(
                            "Justificativa para reprocessar (pode duplicar notificação após timeout):",
                          );
                          if (!reason) return;
                          try {
                            await rpc("retry_notification", {
                              p_id: j.id,
                              p_reason: reason,
                            });
                            await load();
                          } catch (e) {
                            setError(e.message);
                          }
                        }}
                      >
                        Autorizar retry
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </article>
    </section>
  );
}
