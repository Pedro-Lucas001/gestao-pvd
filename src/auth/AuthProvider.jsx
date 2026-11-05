import { useState, useEffect, useCallback, useRef } from "react";
import { AuthContext } from "./context";
import { supabase, rpc } from "../lib/supabase";
export default function AuthProvider({ children }) {
  const [session, setSession] = useState(null),
    [profile, setProfile] = useState(null),
    [loading, setLoading] = useState(true),
    [authError, setAuthError] = useState(""),
    [lease, setLease] = useState(0);
  const epoch = useRef(0);
  const currentUser = useRef(null);
  const profileReady = useRef(false);
  const currentRole = useRef(null);
  const loadProfile = useCallback(async (s) => {
    const current = ++epoch.current;
    currentUser.current = s?.user.id || null;
    profileReady.current = false;
    setSession(s);
    setProfile(null);
    setLease(0);
    setLoading(true);
    setAuthError("");
    if (!s) {
      setLoading(false);
      return;
    }
    const { data, error } = await supabase
      .from("profiles")
      .select("id,name,role,sector,active")
      .eq("id", s.user.id)
      .single();
    if (current !== epoch.current) return;
    if (error)
      setAuthError("Não foi possível verificar seu perfil. Tente novamente.");
    else if (!data.active)
      setAuthError("Seu acesso precisa ser ativado pelo administrador.");
    else {
      setProfile(data);
      profileReady.current = true;
      currentRole.current = data.role;
    }
    setLoading(false);
  }, []);
  useEffect(() => {
    if (!supabase) return;
    let active = true;
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, s) => {
      // Schedule DB access outside the auth callback, avoiding an auth lock deadlock.
      if (!active) return;
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
      const version = epoch.current;
      const {
        data: { session: current },
      } = await supabase.auth.getSession();
      if (!current || !active || version !== epoch.current) return;
      const { data, error } = await supabase
        .from("profiles")
        .select("id,name,role,sector,active")
        .eq("id", current.user.id)
        .single();
      if (
        !active ||
        version !== epoch.current ||
        current.user.id !== currentUser.current
      )
        return;
      if (error || !data?.active) {
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
    if (!lease) return;
    const timer = setTimeout(
      () => setLease(0),
      Math.max(0, lease - Date.now()),
    );
    return () => clearTimeout(timer);
  }, [lease]);
  async function lock() {
    setLease(0);
    await rpc("lock_terminal");
  }
  async function unlock(pin) {
    const result = await rpc("unlock_terminal", { p_pin: pin });
    if (!result.ok) throw new Error(result.error);
    setLease(new Date(result.expires_at).getTime());
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
    if (error)
      setAuthError(
        "Não foi possível encerrar sua sessão no servidor. Reconecte e tente sair novamente.",
      );
  }
  return (
    <AuthContext.Provider
      value={{
        session,
        profile,
        loading,
        authError,
        locked: profile?.role === "cashier" && !lease,
        unlock,
        lock,
        signOut,
        retry: () => loadProfile(session),
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
