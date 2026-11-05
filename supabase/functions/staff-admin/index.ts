import { createClient } from "npm:@supabase/supabase-js@2.99.0";
import { cors, response, readLimited } from "../_shared/http.ts";
Deno.serve(async (req: Request) => {
  const headers = cors(req);
  if (!headers) return response({ error: "ORIGIN_NOT_ALLOWED" }, 403);
  const reply = (v: unknown, s = 200) => {
    const r = response(v, s);
    for (const [k, val] of Object.entries(headers)) r.headers.set(k, val);
    return r;
  };
  if (req.method === "OPTIONS") return reply({ ok: true });
  if (req.method !== "POST") return reply({ error: "METHOD_NOT_ALLOWED" }, 405);
  const auth = req.headers.get("Authorization") || "";
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );
  const {
    data: { user },
    error,
  } = await userClient.auth.getUser();
  if (error || !user) return reply({ error: "AUTH_REQUIRED" }, 401);
  const { data: profile } = await userClient
    .from("profiles")
    .select("role,active")
    .eq("id", user.id)
    .single();
  if (!profile?.active || profile.role !== "admin")
    return reply({ error: "ADMIN_REQUIRED" }, 403);
  try {
    const body = JSON.parse(
      new TextDecoder().decode(await readLimited(req, 8192)),
    );
    if (
      typeof body.email !== "string" ||
      !body.email.includes("@") ||
      typeof body.password !== "string" ||
      body.password.length < 12 ||
      body.password.length > 256 ||
      typeof body.name !== "string" ||
      body.name.trim().length < 2 ||
      !["admin", "cashier", "kitchen"].includes(body.role)
    )
      return reply({ error: "INVALID_STAFF_DATA" }, 400);
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { data, error } = await db.auth.admin.createUser({
      email: body.email,
      password: body.password,
      email_confirm: true,
      user_metadata: { name: body.name.trim() },
    });
    if (error || !data.user)
      return reply({ error: "USER_CREATION_FAILED_CHECK_EXISTING_EMAIL" }, 409);
    const { error: activation } = await userClient.rpc("manage_staff", {
      p_user: data.user.id,
      p_role: body.role,
      p_sector: body.role === "kitchen" ? body.sector : null,
      p_active: true,
      p_reason: "Cadastro autorizado de funcionário pela administração",
    });
    if (activation)
      return reply(
        {
          error: "ACCOUNT_CREATED_INACTIVE_FINISH_IN_TEAM",
          userId: data.user.id,
        },
        409,
      );
    if (body.pin) {
      const { error } = await userClient.rpc("set_staff_pin", {
        p_user: data.user.id,
        p_pin: body.pin,
      });
      if (error)
        return reply(
          { error: "ACCOUNT_CREATED_SET_PIN_IN_TEAM", userId: data.user.id },
          409,
        );
    }
    return reply({ ok: true, userId: data.user.id }, 201);
  } catch (e) {
    return reply(
      {
        error:
          e instanceof RangeError ? "PAYLOAD_TOO_LARGE" : "INVALID_REQUEST",
      },
      400,
    );
  }
});
