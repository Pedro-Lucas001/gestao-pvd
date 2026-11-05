export async function hmacValid(
  raw: Uint8Array,
  signature: string | null,
  secret: string,
): Promise<boolean> {
  if (!signature || !/^sha256=[a-f0-9]{64}$/i.test(signature) || !secret)
    return false;
  const bytes = Uint8Array.from(signature.slice(7).match(/../g)!, (x) =>
    parseInt(x, 16),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify("HMAC", key, bytes, new Uint8Array(raw).buffer);
}
export async function sameSecret(a: string, b: string): Promise<boolean> {
  if (!a || !b) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(b),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(b),
  );
  return crypto.subtle.verify("HMAC", key, sig, new TextEncoder().encode(a));
}
export function faq(text: string, menuUrl: string): string {
  const message = text
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
  if (/horario|abre|fecha/.test(message))
    return "Atendemos de terça a domingo, das 18h às 23h. Segunda-feira fechado. Planeta Lanches, Carpina — PE.";
  if (/endereco|local|onde/.test(message))
    return "Estamos em Carpina — PE. Peça atendimento humano para confirmar o endereço completo e a área de entrega.";
  if (/atendente|humano|ajuda/.test(message))
    return "Sua mensagem está na fila de atendimento da equipe. Aguarde o retorno de um atendente.";
  return menuUrl
    ? `Olá! Aqui é o Planeta Lanches. Consulte o cardápio e faça seu pedido: ${menuUrl}\nVocê também pode perguntar o horário ou pedir atendimento humano.`
    : "Olá! Aqui é o Planeta Lanches. A equipe vai ajudar com o cardápio e seu pedido. Você também pode perguntar o horário ou pedir atendimento humano.";
}
export class MetaClient {
  constructor(
    private token: string,
    private phoneId: string,
    private version = "v23.0",
  ) {
    if (!token || !phoneId.match(/^\d+$/) || !version.match(/^v\d+\.\d+$/))
      throw new Error("WHATSAPP_NOT_CONFIGURED");
  }
  async send(to: string, content: Record<string, unknown>): Promise<string> {
    if (!to.match(/^\d{10,15}$/)) throw new Error("INVALID_RECIPIENT");
    const result = await fetch(
      `https://graph.facebook.com/${this.version}/${this.phoneId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ messaging_product: "whatsapp", to, ...content }),
        signal: AbortSignal.timeout(10000),
      },
    );
    if (!result.ok) throw new Error(`META_HTTP_${result.status}`);
    const data = await result.json();
    if (!data.messages?.[0]?.id) throw new Error("META_RESPONSE_UNCONFIRMED");
    return data.messages[0].id;
  }
  text(to: string, body: string) {
    return this.send(to, { type: "text", text: { preview_url: false, body } });
  }
  status(
    to: string,
    template: string,
    language: string,
    number: string,
    status: string,
  ) {
    return this.send(to, {
      type: "template",
      template: {
        name: template,
        language: { code: language },
        components: [
          {
            type: "body",
            parameters: [
              { type: "text", text: number },
              { type: "text", text: status },
            ],
          },
        ],
      },
    });
  }
}
