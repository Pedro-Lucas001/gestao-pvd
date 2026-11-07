import { useEffect, useState } from "react";
import { ArrowRight, LockKeyhole } from "lucide-react";
import { useAuth } from "./context";
import PinPad from "./PinPad";
import { deviceToken } from "./device";
import { useConnection } from "../components/useConnection";
export default function TerminalLock() {
  const { profile, session, unlock, signIn, signOut } = useAuth(),
    online = useConnection();
  const isAdmin = profile.role === "admin";
  const [pin, setPin] = useState(""),
    [password, setPassword] = useState(""),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [retryAt, setRetryAt] = useState(0),
    [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!retryAt) return;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [retryAt]);
  const remaining = Math.max(0, Math.ceil((retryAt - now) / 1000));
  return (
    <section className="terminal-lock" aria-label="Tela bloqueada">
      <LockKeyhole size={35} />
      <span className="eyebrow">TERMINAL BLOQUEADO</span>
      <h1>Seu espaço está protegido.</h1>
      <p>
        {profile.name}, {isAdmin
          ? "confirme sua senha para voltar à administração."
          : "digite seu PIN para voltar ao trabalho."}{" "}
        O sistema bloqueia após 10 minutos sem atividade.
      </p>
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          if (busy || !online) return;
          setBusy(true);
          setError("");
          try {
            if (isAdmin) {
              const { error } = await signIn({
                email: session.user.email,
                password,
              });
              if (error) {
                throw new Error("Não foi possível confirmar sua senha. Confira os dados e a conexão.");
              }
            } else {
              await unlock(pin);
            }
            setPin("");
            setRetryAt(0);
          } catch (e) {
            setPin("");
            setError(e.message);
            setRetryAt(e.retryAt ? new Date(e.retryAt).getTime() : 0);
            setNow(Date.now());
          } finally {
            setPassword("");
            setBusy(false);
          }
        }}
      >
        {isAdmin ? (
          <>
            <label>
              E-mail da administração
              <input type="email" autoComplete="username" value={session.user.email} readOnly />
            </label>
            <label>
              Confirme sua senha
              <input
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                required
                disabled={busy || !online}
              />
            </label>
          </>
        ) : (
          <PinPad
            value={pin}
            onChange={setPin}
            disabled={remaining > 0 || busy}
            id="unlock-pin"
          />
        )}
        {error && (
          <p className="error-message" role="alert">
            {error}
          </p>
        )}
        {remaining > 0 && (
          <p role="status">
            Tente novamente em {Math.floor(remaining / 60)}:
            {String(remaining % 60).padStart(2, "0")}.
          </p>
        )}
        <button
          className="primary full"
          disabled={!online || busy || (isAdmin ? !password : pin.length !== 4 || remaining > 0)}
        >
          {isAdmin ? "Retomar administração" : "Destravar terminal"}
          <ArrowRight size={17} />
        </button>
      </form>
      {!isAdmin && !deviceToken() && (
        <p className="error-message">
          Este navegador precisa ser cadastrado por um administrador em Equipe e
          acessos.
        </p>
      )}
      {!isAdmin && <small>
        Cinco PINs incorretos consecutivos bloqueiam este terminal por 3
        minutos. O contador é mantido no servidor.
      </small>}
      <button className="text-button" onClick={signOut}>
        Sair e entrar novamente com e-mail e senha
      </button>
    </section>
  );
}
