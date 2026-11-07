import { createHash } from "node:crypto";
import { readFile, readdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = new URL("../", import.meta.url);
const migrationDir = new URL("supabase/migrations/", root);
const migrations = (await readdir(migrationDir)).filter((name) => name.endsWith(".sql")).sort();
const sourcePaths = [...migrations.map((name) => `supabase/migrations/${name}`), "supabase/seed.sql"];
const blocks = [];
for (const path of sourcePaths) {
  const source = await readFile(new URL(path, root), "utf8");
  // Each source owns one top-level transaction. The bundle uses one transaction
  // for the entire install, including its non-empty-database guard and seed.
  if ((source.match(/^begin;\s*$/gmi) || []).length !== 1 ||
      (source.match(/^commit;\s*$/gmi) || []).length !== 1) {
    throw new Error(`Expected one transaction in ${path}; review bundling before installing.`);
  }
  const hash = createHash("sha256").update(source).digest("hex");
  blocks.push(`-- SOURCE: ${path}\n-- SHA256: ${hash}\n${source.replace(/^begin;[ \t]*\r?$/gmi, "").replace(/^commit;[ \t]*\r?$/gmi, "").trim()}\n`);
}

const sql = `-- GERADO por npm run activation:prepare. Não editar manualmente.
-- SOMENTE PARA UM PROJETO SUPABASE NOVO E VAZIO.
-- Contrato em inglês do frontend; NÃO misturar com supabase/sql_editor/.
-- Inclui todas as migrações e seed em uma única transação.
-- NÃO inclui fixtures de testes nem promove usuários a administrador.
begin;
do $activation_guard$
begin
  if exists (
    select 1 from information_schema.tables where table_schema = 'public'
  ) or exists (
    select 1 from pg_namespace where nspname = 'app_private'
  ) or exists (
    select 1 from auth.users
  ) or exists (
    select 1 from storage.buckets
  ) then
    raise exception 'ACTIVATION_REQUIRES_EMPTY_PROJECT: já existem tabelas, usuários, buckets ou estrutura operacional. Use as migrações incrementais após revisar o banco.';
  end if;
end
$activation_guard$;

${blocks.join("\n")}
-- Pedidos públicos começam pausados. Cadastre a loja e homologue antes de abrir.
update public.online_shop_settings set enabled = false, delivery_enabled = false;
commit;
`;

function withoutTransaction(source) {
  if ((source.match(/^begin;[ \t]*$/gm) || []).length !== 1 ||
      (source.match(/^commit;[ \t]*$/gm) || []).length !== 1) {
    throw new Error("Expected one outer transaction before composing activation.");
  }
  return source.replace(/^begin;[ \t]*$/m, "").replace(/^commit;[ \t]*$/m, "");
}
const legacy = await readFile(new URL("supabase/activation/02_preservar_legado_vazio.sql", root), "utf8");
const transition = `-- GERADO por npm run activation:prepare. Não editar manualmente.
-- TRANSIÇÃO ESPECÍFICA: somente legado vazio previamente inspecionado/autorizado.
-- Preserva oito tabelas e funções em schema privado; instala o contrato atual.
-- Uma única transação: qualquer falha desfaz a preservação e a instalação.
-- Não executar 01 ou 02 separadamente depois deste arquivo.
begin;
${withoutTransaction(legacy)}
${withoutTransaction(sql)}
notify pgrst, 'reload schema';
commit;
`;
const outputs = [
  ["supabase/activation/01_instalacao_nova.sql", sql],
  ["supabase/activation/03_transicao_legado_vazio.sql", transition],
];
for (const [path, content] of outputs) {
const output = new URL(path, root);
if (process.argv.includes("--check")) {
  if (await readFile(output, "utf8") !== content) {
    throw new Error("Instalador desatualizado. Execute npm run activation:prepare.");
  }
  console.log(`Instalador conferido: ${migrations.length} migrações + seed, sem alterações no banco.`);
} else {
  await writeFile(output, content);
  console.log(`Instalador gerado: ${fileURLToPath(output)}. Nenhum banco foi acessado.`);
}
}
