import { createClient } from "npm:@supabase/supabase-js@2.99.0";
export async function onlineRpc<T = unknown>(
  name: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const url = Deno.env.get("SUPABASE_URL"),
    key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("BACKEND_NOT_CONFIGURED");
  const db = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (input: RequestInfo | URL, init?: RequestInit) =>
        fetch(input, { ...init, signal: AbortSignal.timeout(12000) }),
    },
  });
  const { data, error } = await db.rpc(name, args);
  if (error) throw new Error(error.message);
  return data as T;
}
export async function sha256(value: string): Promise<string> {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  ]
    .map((v) => v.toString(16).padStart(2, "0"))
    .join("");
}
export async function customerRate(
  req: Request,
  action: string,
  limit: number,
  seconds: number,
) {
  const address = (
    req.headers.get("cf-connecting-ip") ||
    req.headers.get("x-forwarded-for")?.split(",")[0] ||
    "unknown"
  ).slice(0, 100);
  const bucket = await sha256(
    `${Deno.env.get("ONLINE_RATE_SALT") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}:${address}`,
  );
  if (
    !(await onlineRpc<boolean>("online_rate_limit", {
      p_bucket: `${action}:${bucket}`,
      p_limit: limit,
      p_seconds: seconds,
    }))
  )
    throw new Error("RATE_LIMIT");
}
export function publicSite(): string {
  const value = Deno.env.get("PUBLIC_SITE_URL") || "";
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  )
    throw new Error("PUBLIC_SITE_NOT_CONFIGURED");
  return url.origin;
}
