import { useEffect, useState } from "react";
import { ShieldCheck } from "lucide-react";
import { QRCodeSVG } from "qrcode.react";
import { rpc, supabase } from "../lib/supabase";
import { useAuth } from "./context";

export default function AdminMfa({ required = false }) {
  const { profile, retry, signOut, verifyAdminMfa } = useAuth();
  const [factors, setFactors] = useState(null);
  const [enrollment, setEnrollment] = useState(null);
  const [factorId, setFactorId] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [confirmEnforcement, setConfirmEnforcement] = useState(false);

  useEffect(() => {
    let active = true;
    async function loadFactors() {
      try {
        const { data, error } = await supabase.auth.mfa.listFactors();
        if (error) throw error;
        if (active) {
          setFactors(data);
          setFactorId(data.totp[0]?.id || "");
        }
      } catch {
        if (active) setError("Não foi possível consultar seus autenticadores. Recarregue a página.");
      }
    }
    void loadFactors();
    return () => { active = false; };
  }, []);

  async function enroll() {
    setBusy(true);
    setError("");
    try {
      const label = factors.totp.length ? "Planeta Lanches · reserva" : "Planeta Lanches";
      // A refresh can leave an unverified factor. Replace only that draft.
      const draft = factors.all.find((factor) =>
        factor.factor_type === "totp" && factor.status === "unverified" &&
        factor.friendly_name === label
      );
      if (draft) {
        const { error } = await supabase.auth.mfa.unenroll({ factorId: draft.id });
        if (error) throw error;
        setFactors((current) => ({
          ...current,
          all: current.all.filter((factor) => factor.id !== draft.id),
        }));
      }
      const { data, error } = await supabase.auth.mfa.enroll({
        factorType: "totp",
        friendlyName: label,
        issuer: "Planeta Lanches",
      });
      if (error) throw error;
      setEnrollment(data);
      setFactorId(data.id);
    } catch {
      setError("Não foi possível iniciar o cadastro do autenticador. Tente novamente.");
    } finally {
      setBusy(false);
    }
  }

  async function verify(event) {
    event.preventDefault();
    if (!factorId || !/^\d{6}$/.test(code)) return;
    setBusy(true);
    setError("");
    try {
      await verifyAdminMfa(factorId, code);
    } catch {
      setError("Não foi possível confirmar o código. Confira o horário do celular e tente com um novo código.");
    } finally {
      setBusy(false);
      setCode("");
    }
  }

  async function enforce() {
    setBusy(true);
    setError("");
    try {
      await rpc("enable_admin_mfa");
      await retry();
    } catch {
      setError("Não foi possível ativar a exigência. Entre novamente e confirme com seu autenticador.");
    } finally {
      setBusy(false);
    }
  }

  const verifying = enrollment || (required && factors?.totp.length > 0);
  return (
    <section className="management admin-mfa" aria-labelledby="admin-mfa-title">
      <ShieldCheck size={24} />
      <h2 id="admin-mfa-title">
        {required ? "Confirme seu acesso" : "Segurança da conta"}
      </h2>
      <p>
        {verifying
          ? "Digite o código de seis dígitos do seu aplicativo autenticador."
          : "Configure um aplicativo autenticador para proteger o acesso administrativo."}
      </p>
      {!factors && !error && <p role="status">Consultando seus autenticadores…</p>}
      {error && <p className="error-message" role="alert">{error}</p>}
      {enrollment && (
        <div className="admin-mfa-setup">
          <p>Escaneie o QR code com o autenticador ou cadastre a chave manualmente.</p>
          <QRCodeSVG value={enrollment.totp.uri} size={184} title="QR code do autenticador" />
          <details>
            <summary>Mostrar chave de configuração</summary>
            <code>{enrollment.totp.secret}</code>
          </details>
        </div>
      )}
      {verifying && (
        <form onSubmit={verify}>
          {!enrollment && factors.totp.length > 1 && (
            <label>
              Autenticador
              <select value={factorId} onChange={(event) => setFactorId(event.target.value)} disabled={busy}>
                {factors.totp.map((factor, index) => (
                  <option key={factor.id} value={factor.id}>{factor.friendly_name || `Autenticador ${index + 1}`}</option>
                ))}
              </select>
            </label>
          )}
          <label>
            Código do autenticador
            <input
              value={code}
              onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              disabled={busy}
              required
            />
          </label>
          <button className="primary" disabled={busy || code.length !== 6}>Confirmar código</button>
        </form>
      )}
      {factors && !verifying && factors.totp.length < 2 && (
        <button className="secondary" onClick={enroll} disabled={busy}>
          {factors.totp.length ? "Adicionar autenticador reserva" : "Cadastrar autenticador"}
        </button>
      )}
      {!required && !enrollment && factors?.totp.length > 0 && (
        <div className="admin-mfa-policy">
          <p role="status">
            {profile?.admin_mfa_enforced
              ? "Segundo fator obrigatório para a administração."
              : "Seu autenticador está ativo. Você pode exigir o segundo fator de toda a administração."}
          </p>
          {profile?.admin_mfa_enforced === false && (
            <>
              <label className="admin-mfa-confirm">
                <input type="checkbox" checked={confirmEnforcement} onChange={(event) => setConfirmEnforcement(event.target.checked)} />
                Estou com acesso ao meu autenticador. Outros administradores precisarão cadastrar o deles.
              </label>
              <button className="primary" onClick={enforce} disabled={busy || !confirmEnforcement}>
                Exigir segundo fator
              </button>
            </>
          )}
        </div>
      )}
      {required && <button className="text-button" onClick={signOut} disabled={busy}>Sair desta conta</button>}
    </section>
  );
}
