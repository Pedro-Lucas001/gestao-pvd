import { useEffect, useState } from "react";
import { Link, Navigate } from "react-router-dom";
import { ArrowRight, LockKeyhole, ShieldCheck, UserRound } from "lucide-react";
import { useAuth } from "./context";
import { useConnection } from "../components/useConnection";
import { homeForRole } from "./permissions";
import { deviceToken } from "./device";
import Brand from "../components/Brand";
import PinPad from "./PinPad";
import { configured } from "../lib/supabaseConfig";
export default function Login() {
  const {
    profile,
    loading,
    session,
    authError,
    retry,
    signOut,
    signIn,
    signInWithPin,
  } = useAuth();
  const online = useConnection();
  const [mode, setMode] = useState("admin"),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [pin, setPin] = useState(""),
    [retryAt, setRetryAt] = useState(0),
    [now, setNow] = useState(Date.now);
  useEffect(() => {
    if (!retryAt) return;
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, [retryAt]);
  const remaining = Math.max(0, Math.ceil((retryAt - now) / 1000));
  if (!loading && profile && session && !authError) {
    return <Navigate to={homeForRole(profile.role)} replace />;
  }
  async function submitPin(event) {
    event.preventDefault();
    if (busy || remaining || pin.length !== 4) return;
    setBusy(true);
    setError("");
    try {
      await signInWithPin(pin);
    } catch (error) {
      setError(error.message);
      setRetryAt(Date.parse(error.retryAt) || 0);
      setNow(Date.now());
    } finally {
      setBusy(false);
      setPin("");
    }
  }
  return (
    <div className="auth-page">
      <section className="auth-art">
        <Brand />
        <div>
          <span className="eyebrow">O SABOR É NOSSO. O CONTROLE É SEU.</span>
          <h1>
            Uma operação mais leve.
            <br />
            <em>Um pedido de cada vez.</em>
          </h1>
          <p>Do balcão à cozinha, o Planeta continua em movimento.</p>
        </div>
        <img
          src="/brand/planeta-art.png"
          alt="Identidade ilustrada do Planeta Lanches"
        />
        <small>Carpina · PE · Feito com amor</small>
      </section>
      <section className="auth-form">
        <Link className="text-button" to="/cardapio">
          ← Voltar ao cardápio
        </Link>
        <span className="eyebrow">ÁREA INTERNA · ACESSO RESTRITO</span>
        <h2>Vamos começar o turno?</h2>
        <p>
          Entrada exclusiva para funcionários e administração. Seu perfil define
          as áreas disponíveis.
        </p>
        {!configured && (
          <p className="error-message" role="alert">
            A área interna ainda não está disponível neste endereço. Solicite a
            configuração ao administrador.
          </p>
        )}
        <div className="login-tabs" role="tablist" aria-label="Forma de acesso">
          <button
            id="admin-tab"
            role="tab"
            aria-controls="admin-login"
            aria-selected={mode === "admin"}
            className={mode === "admin" ? "active" : ""}
            disabled={busy}
            onClick={() => {
              setMode("admin");
              setError("");
              setPin("");
            }}
          >
            <ShieldCheck size={18} />
            Administração
          </button>
          <button
            id="staff-tab"
            role="tab"
            aria-controls="staff-login"
            aria-selected={mode === "pin"}
            className={mode === "pin" ? "active" : ""}
            disabled={busy}
            onClick={() => {
              setMode("pin");
              setError("");
            }}
          >
            <UserRound size={18} />
            Funcionário · PIN
          </button>
        </div>
        {mode === "admin" ? (
          <form
            id="admin-login"
            role="tabpanel"
            aria-labelledby="admin-tab"
            onSubmit={async (event) => {
              event.preventDefault();
              setBusy(true);
              setError("");
              const body = Object.fromEntries(
                new FormData(event.currentTarget),
              );
              try {
                const { error } = await signIn(body);
                if (error) {
                  setError(
                    "Não foi possível entrar. Confira seu e-mail, senha e conexão.",
                  );
                }
              } catch {
                setError(
                  "Não foi possível entrar. Confira sua conexão e tente novamente.",
                );
              } finally {
                setBusy(false);
              }
            }}
          >
            <label>
              E-mail
              <input
                type="email"
                name="email"
                autoComplete="username"
                required
                placeholder="voce@exemplo.com"
              />
            </label>
            <label>
              Senha
              <input
                type="password"
                name="password"
                autoComplete="current-password"
                required
                minLength={10}
                placeholder="Sua senha"
              />
            </label>
            {(error || authError) && (
              <p className="error-message" role="alert">
                {error || authError}
              </p>
            )}
            <button
              className="primary full"
              disabled={busy || loading || !online || !configured}
            >
              {busy ? "Entrando…" : "Entrar no meu espaço"}
              <ArrowRight size={19} />
            </button>
          </form>
        ) : (
          <form
            id="staff-login"
            className="staff-login-form"
            role="tabpanel"
            aria-labelledby="staff-tab"
            onSubmit={submitPin}
          >
            <p className="pin-login-note">
              Digite seu PIN pessoal. Você será levado diretamente ao caixa ou à
              sua praça na cozinha.
            </p>
            <PinPad
              value={pin}
              onChange={setPin}
              disabled={busy || remaining > 0}
            />
            {(error || authError) && (
              <p className="error-message" role="alert">
                {error || authError}
              </p>
            )}
            {remaining > 0 && (
              <p className="pin-countdown" role="status">
                Aguarde {Math.floor(remaining / 60)}:
                {String(remaining % 60).padStart(2, "0")} para tentar novamente.
              </p>
            )}
            <button
              className="primary full"
              disabled={
                busy ||
                loading ||
                !online ||
                !configured ||
                pin.length !== 4 ||
                remaining > 0
              }
            >
              {busy ? "Validando acesso…" : "Acessar com PIN"}
              <ArrowRight size={19} />
            </button>
            {!deviceToken() && (
              <p className="pin-device-note">
                <LockKeyhole size={17} />
                Primeiro acesso neste dispositivo? Um administrador precisa
                liberar este terminal.
              </p>
            )}
          </form>
        )}
        {session && (!profile || authError) && (
          <div className="auth-retry">
            <button className="secondary" onClick={retry}>
              Verificar perfil novamente
            </button>
            <button className="text-button" onClick={signOut}>
              Sair desta conta
            </button>
          </div>
        )}
        <div className="secure-note">
          <ShieldCheck size={19} />
          <span>
            {mode === "admin"
              ? "Acesso verificado por função. Administração, relatórios e equipe ficam disponíveis apenas ao admin."
              : "PIN individual. Cinco tentativas incorretas bloqueiam o terminal por 3 minutos."}
          </span>
        </div>
        <Link className="text-button" to="/cardapio">
          Sou cliente · consultar cardápio
          <ArrowRight size={15} />
        </Link>
      </section>
    </div>
  );
}
