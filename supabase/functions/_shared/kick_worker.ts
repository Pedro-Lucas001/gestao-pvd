// Best effort only; the minute scheduler remains the durable delivery mechanism.
export function kickWorker(): void {
  const secret = Deno.env.get("INTEGRATION_WORKER_SECRET"), url = Deno.env.get("SUPABASE_URL");
  if (!secret || !url) return;
  const runtime = (globalThis as unknown as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } }).EdgeRuntime;
  if (!runtime) return;
  runtime.waitUntil(fetch(`${url}/functions/v1/integration-worker`, { method: "POST", headers: { "X-Worker-Secret": secret }, signal: AbortSignal.timeout(50000) }).then((r) => r.body?.cancel()).catch(() => undefined));
}
