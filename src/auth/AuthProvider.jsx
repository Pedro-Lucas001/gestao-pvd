import { useCallback, useEffect, useRef, useState } from "react";
import { AuthContext } from "./context";
import { rpc, supabase } from "../lib/supabase";
import { deviceToken } from "./device";
import { useIdleLock } from "./useIdleLock";
async function operatorProfile(userId) {
  const result = await supabase.rpc("operator_context");
  // Compatibilidade do login tradicional até aplicar a migração incremental 012.
  if (result.error?.code === "PGRST202") {
    return supabase.from("profiles").select("id,name,role,sector,active").eq(
      "id",
      userId,
    ).single();
  }
  return result;
}
export default function AuthProvider({ children }) {
  const [session, setSession] = useState(null),
    [profile, setProfile] = useState(null),
    [loading, setLoading] = useState(true),
    [authError, setAuthError] = useState(""),
    [lease, setLease] = useState(0),
    [idleLocked, setIdleLocked] = useState(false);
  const leaseRef = useRef(0),
    lastHeartbeat = useRef(0);
  const epoch = useRef(0);
  const explicitSignIn = useRef(false);
  const currentUser = useRef(null);
  const profileReady = useRef(false);
  const currentRole = useRef(null);
  const loadProfile = useCallback(async (s, resetIdle = false) => {
    const current = ++epoch.current;
    currentUser.current = s?.user.id || null;
    profileReady.current = false;
    setSession(s);
    setProfile(null);
    setLease(0);
    let shouldLock = false;
    if (s) {
      try {
        const stored = JSON.parse(
          sessionStorage.getItem(`planeta:idle:${s.user.id}`) || "null",
        );
        shouldLock = !resetIdle &&
          Boolean(
            stored && (stored.locked || Date.now() - stored.activity >= 600000),
          );
        if (resetIdle) {
          sessionStorage.setItem(
            `planeta:idle:${s.user.id}`,
            JSON.stringify({ locked: false, activity: Date.now() }),
          );
        }
      } catch {
        shouldLock = true;
      }
    }
    setIdleLocked(shouldLock);
    setLoading(true);
    setAuthError("");
    if (!s) {
      setLoading(false);
      return;
    }
    const { data, error } = await operatorProfile(s.user.id);
    if (current !== epoch.current) return;
    if (error) {
      setAuthError("Não foi possível verificar seu perfil. Tente novamente.");
    } else if (!data?.active) {
      setAuthError("Seu acesso precisa ser ativado pelo administrador.");
    } else if (data.requires_password) {
      setAuthError(
        "Acesso administrativo exige uma nova entrada com e-mail e senha.",
      );
    } else {
      setProfile(data);
      profileReady.current = true;
      currentRole.current = data.role;
    }
    setLoading(false);
    return error || !data?.active || data.requires_password ? null : data;
  }, []);
  useEffect(() => {
    if (!supabase) return;
    let active = true;
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, s) => {
      // Schedule DB access outside the auth callback, avoiding an auth lock deadlock.
      if (!active || explicitSignIn.current) return;
      if (
        event === "TOKEN_REFRESHED" ||
        (event === "SIGNED_IN" &&
          s?.user.id === currentUser.current &&
          profileReady.current)
      ) {
        setSession(s);
        return;
      }
      setTimeout(() => {
        if (active) loadProfile(s);
      }, 0);
    });
    const timer = setInterval(async () => {
      if (explicitSignIn.current) return;
      const version = epoch.current;
      const {
        data: { session: current },
      } = await supabase.auth.getSession();
      if (!current || !active || version !== epoch.current) return;
      const { data, error } = await operatorProfile(current.user.id);
      if (
        !active ||
        version !== epoch.current ||
        current.user.id !== currentUser.current
      ) {
        return;
      }
      if (error || !data?.active || data.requires_password) {
        profileReady.current = false;
        setProfile(null);
        setLease(0);
        setAuthError("Seu perfil não pôde ser verificado. Entre novamente.");
      } else {
        if (currentRole.current !== data.role) setLease(0);
        currentRole.current = data.role;
        profileReady.current = true;
        setProfile(data);
        setAuthError("");
      }
    }, 30000);
    return () => {
      active = false;
      subscription.unsubscribe();
      clearInterval(timer);
    };
  }, [loadProfile]);
  useEffect(() => {
    leaseRef.current = lease;
  }, [lease]);
  const persistIdle = useCallback((locked) => {
    if (currentUser.current) {
      try {
        sessionStorage.setItem(
          `planeta:idle:${currentUser.current}`,
          JSON.stringify({ locked, activity: Date.now() }),
        );
      } catch {
        /* Local lock still applies in memory. */
      }
    }
  }, []);
  const lastActivitySave = useRef(0);
  const idleLock = useCallback(() => {
    persistIdle(true);
    setIdleLocked(true);
    setLease(0);
    rpc("lock_terminal").catch(() => {});
  }, [persistIdle]);
  const activity = useCallback(() => {
    if (Date.now() - lastActivitySave.current > 5000) {
      persistIdle(false);
      lastActivitySave.current = Date.now();
    }
    if (!leaseRef.current || Date.now() - lastHeartbeat.current < 30000) return;
    lastHeartbeat.current = Date.now();
    rpc("heartbeat_terminal")
      .then((result) => {
        if (result.ok) setLease(new Date(result.expires_at).getTime());
        else {
          persistIdle(true);
          setLease(0);
          setIdleLocked(true);
        }
      })
      .catch(() => {});
  }, [persistIdle]);
  const locked = Boolean(
    profile &&
      (idleLocked || (["cashier", "kitchen"].includes(profile.role) && !lease)),
  );
  useIdleLock(Boolean(profile) && !locked, idleLock, activity);
  useEffect(() => {
    if (!lease) return;
    const timer = setTimeout(
      () => {
        persistIdle(true);
        setLease(0);
        setIdleLocked(true);
      },
      Math.max(0, lease - Date.now()),
    );
    return () => clearTimeout(timer);
  }, [lease, persistIdle]);
  async function lock() {
    persistIdle(true);
    setLease(0);
    setIdleLocked(true);
    await rpc("lock_terminal");
  }
  async function unlock(pin) {
    const result = await rpc("unlock_terminal", {
      p_pin: pin,
      p_terminal_token: deviceToken(),
    });
    if (!result.ok) {
      const failure = new Error(result.error);
      failure.retryAt = result.retry_at;
      throw failure;
    }
    persistIdle(false);
    setIdleLocked(false);
    setLease(new Date(result.expires_at).getTime());
  }
  async function signIn(body) {
    explicitSignIn.current = true;
    try {
      const result = await supabase.auth.signInWithPassword(body);
      if (!result.error) await loadProfile(result.data.session, true);
      return { error: result.error };
    } finally {
      explicitSignIn.current = false;
    }
  }
  async function signInWithPin(pin) {
    if (!deviceToken()) {
      throw new Error(
        "Este terminal precisa ser cadastrado por um administrador em Equipe e acessos.",
      );
    }
    explicitSignIn.current = true;
    try {
      const { data, error } = await supabase.functions.invoke("fast-pass", {
        body: { pin, terminal_token: deviceToken() },
      });
      if (error) {
        let payload = {};
        try {
          payload = await error.context.json();
        } catch { /* Erro de rede, sem confirmação do servidor. */ }
        const messages = {
          INVALID_PIN:
            "PIN não validado. Confira os quatro dígitos ou procure o administrador.",
          PIN_LOCKED:
            "Terminal bloqueado por 3 minutos após cinco tentativas incorretas.",
          TERMINAL_REQUIRED:
            "Terminal não cadastrado ou revogado. Solicite o cadastro ao administrador.",
        };
        const failure = new Error(
          messages[payload.error] ||
            "Não foi possível acessar. Confira a conexão e a ativação do Fast-Pass.",
        );
        failure.retryAt = payload.retry_at;
        throw failure;
      }
      if (
        !data?.session?.access_token || !data.session.refresh_token ||
        !Number.isFinite(Date.parse(data.lease_expires_at))
      ) throw new Error("O servidor não confirmou o acesso. Tente novamente.");
      const { data: authData, error: authFailure } = await supabase.auth
        .setSession(data.session);
      if (authFailure || !authData.session) {
        throw new Error("Não foi possível validar a sessão do funcionário.");
      }
      const operator = await loadProfile(authData.session, true);
      if (!operator || !["cashier", "kitchen"].includes(operator.role)) {
        await supabase.auth.signOut({ scope: "local" });
        await loadProfile(null);
        throw new Error(
          "Este acesso exige e-mail e senha ou ativação pela administração.",
        );
      }
      persistIdle(false);
      setIdleLocked(false);
      setLease(Date.parse(data.lease_expires_at));
    } finally {
      explicitSignIn.current = false;
    }
  }
  async function signOut() {
    setLease(0);
    if (profile) {
      try {
        sessionStorage.removeItem(`planeta:pdv:${profile.id}`);
      } catch {
        /* Do not block sign out when storage is unavailable. */
      }
    }
    const { error } = await supabase.auth.signOut();
    if (error) {
      setAuthError(
        "Não foi possível encerrar sua sessão no servidor. Reconecte e tente sair novamente.",
      );
    }
  }
  return (
    <AuthContext.Provider
      value={{
        session,
        profile,
        loading,
        authError,
        locked,
        unlock,
        lock,
        signOut,
        signIn,
        signInWithPin,
        retry: () => loadProfile(session),
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
