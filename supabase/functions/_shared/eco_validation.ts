import { hmacValid } from "./meta.ts";
export async function bridgeSignature(input: {
  method: string;
  path: string;
  source: string;
  timestamp: string;
  raw: Uint8Array;
  signature: string | null;
  secret: string;
  now?: number;
}) {
  if (
    !/^[a-z][a-z0-9_-]{1,39}$/.test(input.source) ||
    !/^\d{10}$/.test(input.timestamp) ||
    input.secret.length < 32 ||
    Math.abs((input.now ?? Date.now()) / 1000 - Number(input.timestamp)) > 300
  ) return false;
  const prefix = new TextEncoder().encode(
    `${input.method}\n${input.path}\n${input.source}\n${input.timestamp}\n`,
  );
  const signed = new Uint8Array(prefix.length + input.raw.length);
  signed.set(prefix);
  signed.set(input.raw, prefix.length);
  return hmacValid(signed, input.signature, input.secret);
}
export function command(text: string) {
  const value = text.trim().toLowerCase();
  if (["sair", "parar", "cancelar marketing"].includes(value)) return "optout";
  if (value === "quero receber promoções") return "optin";
  if (value === "confirmar") return "confirm";
  if (/^(privacidade|meus dados|esquecer meus dados|lgpd)$/.test(value)) {
    return "privacy";
  }
  if (/^(humano|atendente)$/.test(value)) return "human";
  return "ai";
}
export type AiItem = {
  product_id: string;
  quantidade: number;
  modificadores: { ingrediente: string; incluir: boolean }[];
  ponto: string | null;
};
export function canonicalModifiers(items: AiItem[]) {
  if (!Array.isArray(items) || items.length < 1 || items.length > 50) {
    throw new Error("INVALID_ITEMS");
  }
  const allowed = [
    "cebola",
    "tomate",
    "alface",
    "milho",
    "batata_palha",
    "queijo",
    "bacon",
  ];
  return items.map((item) => {
    if (
      !/^[a-f0-9-]{36}$/i.test(item.product_id) ||
      !Number.isInteger(item.quantidade) || item.quantidade < 1 ||
      item.quantidade > 999 ||
      !Array.isArray(item.modificadores) || item.modificadores.length > 7
    ) throw new Error("INVALID_ITEM");
    const modifiers: Record<string, boolean | string> = {};
    for (const m of item.modificadores) {
      if (
        !allowed.includes(m.ingrediente) || typeof m.incluir !== "boolean" ||
        m.ingrediente in modifiers
      ) throw new Error("INVALID_MODIFIER");
      modifiers[m.ingrediente] = m.incluir;
    }
    if (item.ponto !== null) {
      if (!["bem passado", "ao ponto", "mal passado"].includes(item.ponto)) {
        throw new Error("INVALID_POINT");
      }
      modifiers.ponto = item.ponto;
    }
    return {
      product_id: item.product_id,
      quantidade: item.quantidade,
      modificadores: modifiers,
    };
  });
}
