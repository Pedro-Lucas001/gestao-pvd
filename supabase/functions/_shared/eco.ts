// Contrato SQL em português: supabase/sql_editor/, não migrations/.
import { createClient } from "npm:@supabase/supabase-js@2.99.0";
import { readLimited } from "./http.ts";
export function ecoDb() {
  const url = Deno.env.get("SUPABASE_URL"),
    key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("BACKEND_NOT_CONFIGURED");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (input, init) =>
        fetch(input, { ...init, signal: AbortSignal.timeout(12000) }),
    },
  });
}
export async function bodyJson(req: Request): Promise<Record<string, unknown>> {
  const data = JSON.parse(new TextDecoder().decode(await readLimited(req)));
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("INVALID_BODY");
  }
  return data;
}
export function json(
  data: unknown,
  status = 200,
  headers: Record<string, string> = {},
) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      ...headers,
    },
  });
}
export class EcoRejected extends Error {
  constructor(public code: string) {
    super("OPERATION_REJECTED");
  }
}
export async function ecoRpc<T>(
  name: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const { data, error } = await ecoDb().rpc(name, args);
  if (error) throw new EcoRejected(error.code);
  return data as T;
}
export function kickWorker() {
  const runtime = (globalThis as unknown as {
    EdgeRuntime?: { waitUntil(p: Promise<unknown>): void };
  }).EdgeRuntime;
  const secret = Deno.env.get("ECO_WORKER_SECRET"),
    url = Deno.env.get("SUPABASE_URL");
  if (!runtime || !secret || !url) return; // O agendador permanece obrigatório como fallback.
  runtime.waitUntil(
    fetch(`${url}/functions/v1/eco-worker`, {
      method: "POST",
      headers: { "X-Worker-Secret": secret },
      signal: AbortSignal.timeout(65000),
    }).then((r) => r.body?.cancel()).catch(() => undefined),
  );
}
