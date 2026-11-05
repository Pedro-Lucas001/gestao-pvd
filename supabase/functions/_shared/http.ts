export function response(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
export function cors(request: Request): Record<string, string> | null {
  const origin = request.headers.get("Origin");
  const allowed = (Deno.env.get("APP_ALLOWED_ORIGINS") || "")
    .split(",")
    .map((x) => x.trim());
  return origin && allowed.includes(origin)
    ? {
        "Access-Control-Allow-Origin": origin,
        Vary: "Origin",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      }
    : null;
}

export async function readLimited(
  request: Request,
  maximum = 65536,
): Promise<Uint8Array> {
  if (Number(request.headers.get("Content-Length") || 0) > maximum)
    throw new RangeError("PAYLOAD_TOO_LARGE");
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const parts: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maximum) {
      await reader.cancel();
      throw new RangeError("PAYLOAD_TOO_LARGE");
    }
    parts.push(value);
  }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.byteLength;
  }
  return result;
}
