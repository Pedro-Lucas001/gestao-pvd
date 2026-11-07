import { useEffect, useState } from "react";
import { supabase, rpc } from "../lib/supabase";
import TerminalSetup from "./TerminalSetup";
import StaffCreate from "./StaffCreate";
import { roleDescriptions } from "../auth/modules";
import "./AdminControl.css";
export function StaffAccessForm({ person, onSave, busy }) {
  const [role, setRole] = useState(person.role),
    [active, setActive] = useState(person.active),
    [pin, setPin] = useState("");
  return (
    <form
      className="staff-row"
      onSubmit={(e) => {
        e.preventDefault();
        const form = e.currentTarget;
        const f = new FormData(form);
        onSave(
          {
            p_user: person.id,
            p_role: role,
            p_sector: role === "kitchen" ? f.get("sector") : null,
            p_active: active,
            p_pin: role === "admin" ? null : pin || null,
            p_reason: f.get("reason"),
          },
          () => {
            setPin("");
            form.reset();
          },
        );
      }}
    >
      <strong>{person.name}</strong>
      <fieldset disabled={busy}>
        <label>
          Função
          <select
            value={role}
            onChange={(e) => {
              setRole(e.target.value);
              setPin("");
            }}
          >
            <option value="cashier">Funcionário · caixa e atendimento</option>
            <option value="kitchen">Funcionário · cozinha</option>
            <option value="admin">Administrador</option>
          </select>
        </label>
        {role === "kitchen" && (
          <label>
            Setor
            <select name="sector" defaultValue={person.sector || "grill"}>
              <option value="grill">Chapa</option>
              <option value="fryer">Fritura</option>
              <option value="bar">Bebidas</option>
            </select>
          </label>
        )}
        <label>
          Acesso
          <select
            value={String(active)}
            onChange={(e) => setActive(e.target.value === "true")}
          >
            <option value="true">Ativo</option>
            <option value="false">Bloqueado</option>
          </select>
        </label>
        {role !== "admin" && (
          <label>
            Novo PIN pessoal
            <input
              type="password"
              inputMode="numeric"
              pattern="[0-9]{4}"
              minLength={4}
              maxLength={4}
              autoComplete="new-password"
              value={pin}
              onChange={(e) =>
                setPin(e.target.value.replace(/\D/g, "").slice(0, 4))
              }
              placeholder="Manter o PIN atual"
              disabled={!active}
            />
          </label>
        )}
        <label>
          Justificativa
          <input name="reason" required minLength={5} maxLength={500} />
        </label>
        <button className="primary" disabled={busy}>
          Salvar acesso
        </button>
      </fieldset>
      <small className="staff-pin-note">
        {role === "admin"
          ? "Administrador entra com e-mail e senha."
          : "PIN exclusivo de 4 dígitos. Esta pessoa entra na Área do funcionário; os módulos seguem a função atribuída."}
      </small>
    </form>
  );
}
export default function Team() {
  const [team, setTeam] = useState([]),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [success, setSuccess] = useState("");
  async function load() {
    const { data, error } = await supabase
      .from("profiles")
      .select("id,name,role,sector,active")
      .order("name");
    if (error) setError("Não foi possível consultar a equipe.");
    else setTeam(data);
  }
  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, []);
  async function save(args, done) {
    setBusy(true);
    setError("");
    setSuccess("");
    try {
      await rpc("admin_save_staff_access", args);
      done();
      setSuccess(
        "Acesso salvo. O funcionário já pode usar seu PIN no terminal cadastrado.",
      );
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="management">
      <span className="eyebrow">PESSOAS E SEGURANÇA</span>
      <h1>Equipe e PINs de acesso.</h1>
      <p>
        Crie uma conta para cada funcionário e defina seu PIN pessoal. Todos
        entram na mesma Área do funcionário; caixa e cozinha recebem os módulos
        da própria função. Administradores usam e-mail e senha.
      </p>
      <article className="management-panel access-overview">
        <h2>O que cada pessoa pode acessar</h2>
        <div className="access-table-scroll">
          <table>
            <thead>
              <tr>
                <th>Perfil</th>
                <th>Permissão</th>
              </tr>
            </thead>
            <tbody>
              {roleDescriptions.map((r) => (
                <tr key={r.role}>
                  <th>{r.name}</th>
                  <td>{r.scope}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </article>
      <StaffCreate onCreated={load} />
      <TerminalSetup />
      {success && (
        <p role="status" className="control-success">
          {success}
        </p>
      )}
      {error && (
        <p role="alert" className="error-message">
          {error}
        </p>
      )}
      <article className="management-panel">
        <h2>Pessoas da equipe</h2>
        <button className="secondary" onClick={load}>
          Atualizar equipe
        </button>
        {team.map((p) => (
          <StaffAccessForm
            key={`${p.id}:${p.role}:${p.active}:${p.sector}`}
            person={p}
            onSave={save}
            busy={busy}
          />
        ))}
      </article>
    </section>
  );
}
