import {
  readFile,
  writeFile,
  rename,
  mkdir,
  unlink,
  open,
} from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { receiptText } from "./receipt.mjs";

if (process.platform !== "win32")
  throw new Error("Este agente usa a impressora instalada no Windows.");
const base = join(process.env.LOCALAPPDATA || "", "PlanetaLanchesPrint");
const config = JSON.parse(await readFile(join(base, "config.json"), "utf8"));
const url = new URL(config.supabase_url);
if (
  url.protocol !== "https:" ||
  url.username ||
  url.password ||
  url.search ||
  url.hash ||
  url.pathname !== "/" ||
  !/^[a-f0-9]{64}$/.test(config.token) ||
  !config.printer_name ||
  ![58, 80].includes(config.paper_mm)
)
  throw new Error("Configuracao de impressao invalida.");
const endpoint = new URL("/functions/v1/print-agent", url);
const journalDir = join(base, "journal");
await mkdir(journalDir, { recursive: true });
// Avoid two local agents taking over the same journal. A stale lock is removed
// manually only after confirming the previous process is no longer running.
const lock = await open(join(base, "agent.lock"), "wx").catch(() => {
  throw new Error(
    "Agente ja aberto ou encerrado inesperadamente. Confira o processo antes de remover agent.lock.",
  );
});
await lock.writeFile(String(process.pid));
let stopping = false;
process.on("SIGINT", () => {
  stopping = true;
});
process.on("SIGTERM", () => {
  stopping = true;
});
const delay = () => new Promise((resolve) => setTimeout(resolve, 5000));
const run = promisify(execFile);
const journal = join(journalDir, "current.json");
async function save(value) {
  await writeFile(`${journal}.tmp`, JSON.stringify(value), { mode: 0o600 });
  await rename(`${journal}.tmp`, journal);
}
async function api(body) {
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: config.publishable_key,
      "x-print-token": config.token,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) {
    const result = await response.json().catch(() => ({}));
    throw new Error(
      result.error === "PRINT_CLAIM_SUPERSEDED"
        ? result.error
        : "PRINT_SERVER_UNAVAILABLE",
    );
  }
  return response.json();
}
async function recover() {
  const state = await readFile(journal, "utf8")
    .then(JSON.parse)
    .catch((e) => {
      if (e.code === "ENOENT") return null;
      throw e;
    });
  if (!state) return;
  // Crash after Print() or loss of acknowledgement never automatically prints
  // again. A started journal is explicitly reported as uncertain.
  try {
    await api({
      action: "finish",
      id: state.id,
      claim: state.claim,
      success: state.state === "submitted",
    });
  } catch (error) {
    if (error.message !== "PRINT_CLAIM_SUPERSEDED") throw error;
    console.log(
      "Tentativa substituida no painel. Diario encerrado sem repetir o cupom antigo.",
    );
  }
  await unlink(journal);
}
console.log(
  "Agente iniciado. Aguardando pedidos; mantenha este computador ligado.",
);
try {
  while (!stopping) {
    try {
      await recover();
      const job = await api({ action: "claim" });
      if (job) {
        const text = receiptText(job.payload, config.paper_mm === 58 ? 32 : 42);
        const receipt = join(base, "receipt.txt");
        await save({ id: job.id, claim: job.claim, state: "started" });
        try {
          await writeFile(receipt, text, { mode: 0o600 });
          await run(
            "powershell.exe",
            [
              "-NoProfile",
              "-NonInteractive",
              "-File",
              join(
                dirname(fileURLToPath(import.meta.url)),
                "Print-Receipt.ps1",
              ),
              "-ReceiptPath",
              receipt,
              "-PrinterName",
              config.printer_name,
              "-PaperMm",
              String(config.paper_mm),
            ],
            { timeout: 90000, windowsHide: true, maxBuffer: 16384 },
          );
          await save({ id: job.id, claim: job.claim, state: "submitted" });
        } finally {
          await unlink(receipt).catch(() => {});
        }
        await recover();
        console.log("Cupom enviado ao Windows. Confira o papel na impressora.");
      }
    } catch {
      console.error(
        "Impressao ou conexao sem confirmacao. Confira o painel de impressao e a impressora; o agente tentara reconectar sem repetir o cupom.",
      );
    }
    if (!stopping) await delay();
  }
} finally {
  await lock.close();
  await unlink(join(base, "agent.lock"));
}
