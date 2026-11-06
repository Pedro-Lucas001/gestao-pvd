import { useEffect, useState } from "react";
import { supabase, rpc } from "../lib/supabase";
import TerminalSetup from "./TerminalSetup";
import StaffCreate from "./StaffCreate";
import { roleDescriptions } from "../auth/modules";
export default function Team() {
  const [team, setTeam] = useState([]),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
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
  return (
    <section className="management">
      <span className="eyebrow">PESSOAS E SEGURANÇA</span>
      <h1>Equipe e acessos.</h1>
      <p>
        Contas individuais e permissões por função. Funcionários usam o PIN pessoal em terminais cadastrados ou e-mail e senha; administradores entram com e-mail e senha.
      </p>
      <article className="management-panel access-overview">
        <h2>O que cada pessoa pode acessar</h2>
        <p>Cliente: somente o cardápio público, sem login. As áreas abaixo são exclusivas da equipe.</p>
        <div className="access-table-scroll"><table><thead><tr><th scope="col">Perfil</th><th scope="col">Permissão</th></tr></thead><tbody>{roleDescriptions.map((r) => <tr key={r.role}><th scope="row">{r.name}</th><td>{r.scope}</td></tr>)}</tbody></table></div>
      </article>
      <StaffCreate onCreated={load} />
      <TerminalSetup />
      <article className="management-panel">
        <h2>Pessoas da equipe</h2>
        <button className="secondary" onClick={load}>
          Atualizar equipe
        </button>
        {team.map((p) => (
          <form
            className="staff-row"
            key={p.id}
            onSubmit={async (e) => {
              e.preventDefault();
              setBusy(true);
              setError("");
              const f = new FormData(e.currentTarget),
                role = f.get("role"),
                active = f.get("active") === "true";
              try {
                if (f.get("pin") && !active)
                  throw new Error("Ative o acesso antes de definir o PIN.");
                await rpc("manage_staff", {
                  p_user: p.id,
                  p_role: role,
                  p_sector: role === "kitchen" ? f.get("sector") : null,
                  p_active: active,
                  p_reason: f.get("reason"),
                });
                if (f.get("pin"))
                  await rpc("set_staff_pin", {
                    p_user: p.id,
                    p_pin: f.get("pin"),
                  });
                await load();
              } catch (e) {
                setError(e.message);
              } finally {
                setBusy(false);
              }
            }}
          >
            <strong>{p.name}</strong>
            <label>
              Função
              <select name="role" defaultValue={p.role}>
                <option value="cashier">Caixa</option>
                <option value="kitchen">Cozinha</option>
                <option value="admin">Administrador</option>
              </select>
            </label>
            <label>
              Setor
              <select name="sector" defaultValue={p.sector || "grill"}>
                <option value="grill">Chapa</option>
                <option value="fryer">Fritura</option>
                <option value="bar">Bebidas</option>
              </select>
            </label>
            <label>
              Acesso
              <select name="active" defaultValue={String(p.active)}>
                <option value="true">Ativo</option>
                <option value="false">Bloqueado</option>
              </select>
            </label>
            <label>
              Novo PIN pessoal
              <input
                name="pin"
                type="password"
                pattern="[0-9]{4}"
                minLength={4}
                maxLength={4}
                inputMode="numeric"
                autoComplete="new-password"
                placeholder="Opcional"
              />
            </label>
            <label>
              Justificativa
              <input name="reason" required minLength={5} maxLength={500} />
            </label>
            <button className="primary" disabled={busy}>
              Salvar acesso
            </button>
          </form>
        ))}
      </article>
      {error && (
        <p className="error-message" role="alert">
          {error}
        </p>
      )}
    </section>
  );
}
