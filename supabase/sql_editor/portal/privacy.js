// Portal independente, sem cookies, analytics, sessão de funcionário ou armazenamento local.
const root = document.querySelector("main");
const status = document.querySelector("#status");
const controls = [...document.querySelectorAll("button")];
const token = new URLSearchParams(location.hash.slice(1)).get("token") || "";
history.replaceState(null, "", location.pathname + location.search);
const valid = /^[a-f0-9]{64}$/.test(token);
let busy = false;
let forgotten = false;
function refresh() {
  controls.forEach((button) => {
    button.disabled = !valid || busy || forgotten ||
      (button.id === "forget" &&
        !document.querySelector("#confirm-forget").checked);
  });
}
status.textContent = valid
  ? "Link carregado. Escolha o que deseja fazer."
  : "Link ausente ou inválido. Peça outro enviando PRIVACIDADE no WhatsApp.";
refresh();
document.querySelector("#confirm-forget").addEventListener("change", refresh);
async function act(action) {
  if (!valid || busy || forgotten) return;
  busy = true;
  refresh();
  status.textContent = "Processando…";
  try {
    const endpoint = new URL(root.dataset.apiUrl);
    if (
      endpoint.hostname.startsWith("seu-projeto") ||
      endpoint.protocol !== "https:"
    ) throw new Error("CONFIG");
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token, acao: action }),
      credentials: "omit",
      cache: "no-store",
      referrerPolicy: "no-referrer",
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error("UNAVAILABLE");
    const data = await response.json();
    if (action === "acesso") {
      const objectUrl = URL.createObjectURL(
        new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }),
      );
      const link = document.createElement("a");
      link.href = objectUrl;
      link.download = "meus-dados-planeta-lanches.json";
      link.click();
      setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
      status.textContent =
        "Relatório gerado. Guarde o arquivo em local seguro.";
    } else if (action === "anonimizacao") {
      forgotten = true;
      status.textContent = `${
        data.status === "concluido"
          ? "Dados de contato e conversas apagados."
          : "Solicitação registrada. A exclusão será concluída ao encerrar os pedidos em andamento."
      } Protocolo: ${data.protocolo}`;
    } else {status.textContent = action === "consentir_anuncios"
        ? "Você autorizou a medição de anúncios."
        : "Autorização de anúncios revogada.";}
  } catch (error) {
    status.textContent = error.message === "CONFIG"
      ? "Portal aguardando configuração pelo estabelecimento."
      : "Não foi possível confirmar a operação. O link pode ter expirado. Você pode tentar novamente ou solicitar outro pelo WhatsApp.";
  } finally {
    busy = false;
    refresh();
  }
}
document.querySelector("#export").addEventListener(
  "click",
  () => act("acesso"),
);
document.querySelector("#forget").addEventListener(
  "click",
  () => act("anonimizacao"),
);
document.querySelector("#allow-ads").addEventListener(
  "click",
  () => act("consentir_anuncios"),
);
document.querySelector("#deny-ads").addEventListener(
  "click",
  () => act("revogar_anuncios"),
);
