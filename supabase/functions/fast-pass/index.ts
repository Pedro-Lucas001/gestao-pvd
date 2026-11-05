import { createClient } from "npm:@supabase/supabase-js@2.99.0";
import { cors, readLimited, response } from "../_shared/http.ts";
Deno.serve(async (req: Request) => {
  const headers = cors(req);
  const reply = (body: unknown, status = 200) => {
    const result = response(body, status);
    for (const [key, value] of Object.entries(headers || {})) {
      result.headers.set(key, value);
    }
    return result;
  };
  if (!headers) return reply({ error: "ORIGIN_DENIED" }, 403);
  if (req.method === "OPTIONS") return reply({ ok: true });
  if (req.method !== "POST") return reply({ error: "METHOD_NOT_ALLOWED" }, 405);
  const url = Deno.env.get("SUPABASE_URL"),
    secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !secret || !key) {
    return reply({ error: "FASTPASS_UNAVAILABLE" }, 503);
  }
  const options = {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (input: RequestInfo | URL, init?: RequestInit) =>
        fetch(input, { ...init, signal: AbortSignal.timeout(12000) }),
    },
  };
  const admin = createClient(url, secret, options);
  const auth = createClient(url, key, options);
  try {
    const body = JSON.parse(
      new TextDecoder().decode(await readLimited(req, 1024)),
    );
    // Não registrar PIN, token de terminal, link de Auth nem sessão em logs.
    if (
      typeof body.pin !== "string" || !/^[0-9]{4}$/.test(body.pin) ||
      typeof body.terminal_token !== "string" ||
      !/^[a-f0-9]{64}$/.test(body.terminal_token)
    ) return reply({ error: "INVALID_REQUEST" }, 400);
    const { data: proof, error } = await admin.rpc("authenticate_staff_pin", {
      p_pin: body.pin,
      p_terminal_token: body.terminal_token,
    });
    if (error) return reply({ error: "FASTPASS_UNAVAILABLE" }, 503);
    if (!proof?.ok) {
      return reply({
        error: proof?.error || "INVALID_PIN",
        retry_at: proof?.retry_at,
      }, proof?.retry_at ? 429 : 401);
    }
    const { data: account, error: accountError } = await admin.auth.admin
      .getUserById(proof.user_id);
    if (accountError || !account.user?.email) {
      return reply({ error: "FASTPASS_UNAVAILABLE" }, 503);
    }
    // generateLink gera prova de uso único NO SERVIDOR e não envia e-mail.
    const { data: link, error: linkError } = await admin.auth.admin
      .generateLink({ type: "magiclink", email: account.user.email });
    if (linkError || !link.properties?.hashed_token) {
      return reply({ error: "FASTPASS_UNAVAILABLE" }, 503);
    }
    const { data: verified, error: verifyError } = await auth.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.properties.hashed_token,
    });
    if (
      verifyError || !verified.user || verified.user.id !== proof.user_id ||
      !verified.session
    ) return reply({ error: "FASTPASS_UNAVAILABLE" }, 503);
    const session = verified.session;
    // Token veio diretamente do Auth verificado; não decodificamos JWT enviado pelo cliente.
    const claims = JSON.parse(
      atob(
        session.access_token.split(".")[1].replace(/-/g, "+").replace(
          /_/g,
          "/",
        ),
      ),
    );
    const { data: lease, error: bindError } = await admin.rpc(
      "bind_fastpass_session",
      {
        p_user: verified.user.id,
        p_session_id: claims.session_id,
        p_challenge: proof.challenge,
      },
    );
    if (bindError || !lease?.ok) {
      await auth.auth.signOut({ scope: "local" });
      return reply({ error: "FASTPASS_UNAVAILABLE" }, 503);
    }
    return reply({
      session: {
        access_token: session.access_token,
        refresh_token: session.refresh_token,
        expires_at: session.expires_at,
        expires_in: session.expires_in,
        token_type: session.token_type,
      },
      lease_expires_at: lease.expires_at,
    });
  } catch (error) {
    return reply({
      error: error instanceof RangeError
        ? "PAYLOAD_TOO_LARGE"
        : "FASTPASS_UNAVAILABLE",
    }, error instanceof RangeError ? 413 : 503);
  }
});
