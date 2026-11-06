import {
  configured,
  supabaseUrl,
  supabasePublicKey,
} from "../lib/supabaseConfig";
import { fetchWithTimeout } from "../lib/network";
import { publicProducts } from "./menuData";

export { configured };

export async function loadPublicMenu(signal) {
  // Requisição anônima: não lê storage nem compartilha a sessão dos funcionários.
  const response = await fetchWithTimeout(
    `${supabaseUrl}/rest/v1/rpc/public_menu`,
    {
      method: "POST",
      signal,
      headers: {
        apikey: supabasePublicKey,
        Authorization: `Bearer ${supabasePublicKey}`,
        "Content-Type": "application/json",
      },
      body: "{}",
      cache: "no-store",
    },
  );
  if (!response.ok) throw new Error("Não foi possível atualizar o cardápio.");
  return publicProducts(await response.json());
}
