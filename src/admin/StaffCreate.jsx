import { useState } from "react";
import { supabase } from "../lib/supabase";
import { roleDescriptions } from "../auth/modules";

const messages = {
  AUTH_REQUIRED: "Sua sessão expirou. Entre novamente.",
  ADMIN_REQUIRED:
    "Somente a administração autenticada com e-mail e senha pode criar acessos.",
  INVALID_STAFF_DATA:
    "Confira os dados. Use uma senha com pelo menos 12 caracteres.",
  USER_CREATION_FAILED_CHECK_EXISTING_EMAIL:
    "Não foi possível criar a conta. Confira se o e-mail já está cadastrado.",
  ACCOUNT_CREATED_INACTIVE_FINISH_IN_TEAM:
    "A conta foi criada, mas precisa ser ativada na lista da equipe abaixo.",
  ACCOUNT_CREATED_SET_PIN_IN_TEAM:
    "A conta foi criada. Defina um PIN disponível na lista da equipe abaixo.",
};

export default function StaffCreate({ onCreated }) {
  const [role, setRole] = useState("cashier");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  async function submit(event) {
    event.preventDefault();
    if (busy) return;
    const form = event.currentTarget;
    const data = Object.fromEntries(new FormData(form));
    setBusy(true);
    setError("");
    setSuccess("");
    try {
      const result = await supabase.functions.invoke("staff-admin", {
        body: {
          ...data,
          name: data.name.trim(),
          email: data.email.trim(),
          role,
          sector: role === "kitchen" ? data.sector : null,
          pin: data.pin || undefined,
        },
      });
      if (result.error) {
        let failure = {};
        try {
          failure = await result.error.context?.json();
        } catch {
          /* Resposta sem corpo JSON. */
        }
        if (failure?.userId) await onCreated();
        throw new Error(
          messages[failure?.error] ||
            "Não foi possível criar o acesso. Confira a conexão e a ativação do cadastro de equipe.",
        );
      }
      if (!result.data?.ok)
        throw new Error("O servidor não confirmou a criação do acesso.");
      form.reset();
      setRole("cashier");
      setSuccess(
        "Conta criada. Entregue as credenciais apenas à pessoa responsável pelo acesso.",
      );
      await onCreated();
    } catch (failure) {
      setError(failure.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <details className="management-panel staff-create">
      <summary>Criar acesso da equipe</summary>
      <p>
        Use uma conta individual para cada pessoa. O cliente consulta o cardápio
        sem cadastro.
      </p>
      <form onSubmit={submit}>
        <fieldset disabled={busy}>
          <label>
            Nome
            <input
              name="name"
              required
              minLength={2}
              maxLength={100}
              autoComplete="off"
            />
          </label>
          <label>
            E-mail da pessoa
            <input name="email" type="email" required autoComplete="off" />
          </label>
          <label>
            Senha inicial
            <input
              name="password"
              type="password"
              required
              minLength={12}
              maxLength={256}
              autoComplete="new-password"
            />
          </label>
          <label>
            Função
            <select
              name="role"
              value={role}
              onChange={(e) => setRole(e.target.value)}
            >
              {roleDescriptions.map((r) => (
                <option key={r.role} value={r.role}>
                  {r.name}
                </option>
              ))}
            </select>
          </label>
          {role === "kitchen" && (
            <label>
              Setor da cozinha
              <select name="sector" required>
                <option value="grill">Chapa</option>
                <option value="fryer">Fritura</option>
                <option value="bar">Bebidas</option>
              </select>
            </label>
          )}
          {role !== "admin" && (
            <label>
              PIN pessoal exclusivo (4 dígitos)
              <input
                name="pin"
                required
                type="password"
                inputMode="numeric"
                pattern="[0-9]{4}"
                minLength={4}
                maxLength={4}
                autoComplete="new-password"
              />
            </label>
          )}
        </fieldset>
        <button className="primary" disabled={busy}>
          {busy ? "Criando acesso…" : "Criar conta individual"}
        </button>
      </form>
      {error && (
        <p role="alert" className="error-message">
          {error}
        </p>
      )}
      {success && <p role="status">{success}</p>}
    </details>
  );
}
