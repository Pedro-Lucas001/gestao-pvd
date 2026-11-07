import {
  configured,
  supabaseUrl,
  supabasePublicKey,
} from "../lib/supabaseConfig";
import { fetchWithTimeout } from "../lib/network";
export { configured };
export async function customerApi(
  action,
  body = {},
  signal,
  endpoint = "customer-api",
) {
  if (!configured)
    throw new Error(
      "Os pedidos online ainda não estão disponíveis neste endereço.",
    );
  const response = await fetchWithTimeout(
    `${supabaseUrl}/functions/v1/${endpoint}`,
    {
      method: "POST",
      signal,
      headers: {
        apikey: supabasePublicKey,
        Authorization: `Bearer ${supabasePublicKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ action, ...body }),
      cache: "no-store",
    },
    fetch,
    endpoint === "customer-assistant" ? 40000 : 30000,
  );
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(
      data.error || "Não foi possível concluir. Retome a mesma tentativa.",
    );
    error.code = data.code;
    throw error;
  }
  return data;
}
