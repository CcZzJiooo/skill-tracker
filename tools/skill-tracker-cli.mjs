#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dashboard = path.join(root, "dashboard");
const args = process.argv.slice(2);

function usage() {
  console.log(`Skill Tracker CLI\n\n  collect       run the local collector\n  open          start the local dashboard server\n  health        print an explainable skill health report\n  export FILE   export an anonymous aggregate report\n  import FILE   validate and summarize an anonymous report\n  benchmark DIR compare anonymous reports in a directory\n\nOptions: --json writes machine-readable output for health/export/import/benchmark.`);
}

function readJson(file) { return JSON.parse(fs.readFileSync(file, "utf8").replaceAll("\uFEFF", "")); }
function writeJson(file, value) { fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n", "utf8"); }
function generatedAt() { return new Date().toISOString(); }
function rows() {
  const file = path.join(dashboard, "skill_log.js");
  if (!fs.existsSync(file)) return [];
  const text = fs.readFileSync(file, "utf8").replaceAll("\uFEFF", "");
  const match = text.match(/(?:window\.|var\s+)?SKILL_LOG\s*=\s*(\[[\s\S]*?\]);/);
  if (!match) return [];
  return JSON.parse(match[1].replace(/\uFEFF/g, ""));
}
function catalog() {
  const file = path.join(dashboard, "skill_catalog.json");
  return fs.existsSync(file) ? readJson(file) : [];
}
function healthReport() {
  const log = rows();
  const catalogRows = catalog();
  const bySkill = new Map();
  for (const row of log) {
    const name = row.skill || row.skill_name;
    if (!name) continue;
    const item = bySkill.get(name) || { skill: name, calls: 0, raw_calls: 0, tools: new Set(), latest: "", sessions: new Set() };
    item.calls += row.dedup === false ? 0 : 1;
    item.raw_calls += 1;
    if (row.tool) item.tools.add(row.tool);
    if (row.session) item.sessions.add(row.session);
    if (row.time && (!item.latest || row.time > item.latest)) item.latest = row.time;
    bySkill.set(name, item);
  }
  const catalogMap = new Map(catalogRows.map((item) => [item.skill || item.name, item]));
  const now = Date.now();
  const skills = [...bySkill.values()].map((item) => {
    const meta = catalogMap.get(item.skill) || {};
    const ageDays = item.latest ? Math.max(0, (now - Date.parse(item.latest)) / 86400000) : Infinity;
    const duplicateRate = item.raw_calls ? 1 - item.calls / item.raw_calls : 0;
    const reasons = [];
    if (ageDays > 30) reasons.push("长期未使用");
    if (duplicateRate > 0.6) reasons.push("短时间重复读取率高");
    if (!meta.description && !meta.desc && !meta.zh_desc) reasons.push("缺少说明");
    const action = reasons.includes("缺少说明") ? "rewrite" : reasons.includes("长期未使用") ? "observe" : reasons.includes("短时间重复读取率高") ? "merge" : "keep";
    return { skill: item.skill, calls: item.calls, raw_calls: item.raw_calls, tools: [...item.tools].sort(), sessions: item.sessions.size, latest: item.latest, duplicate_rate: Number(duplicateRate.toFixed(3)), health: action, reasons };
  }).sort((a, b) => b.calls - a.calls || a.skill.localeCompare(b.skill));
  return { schema: "skill-tracker-health@1", generated_at: generatedAt(), source_generated_at: readGeneratedAt(), skills, summary: { skills: skills.length, keep: skills.filter((x) => x.health === "keep").length, merge: skills.filter((x) => x.health === "merge").length, rewrite: skills.filter((x) => x.health === "rewrite").length, observe: skills.filter((x) => x.health === "observe").length } };
}
function readGeneratedAt() {
  const file = path.join(dashboard, "skill_data.js");
  const match = fs.existsSync(file) && fs.readFileSync(file, "utf8").match(/GENERATED_AT\s*=\s*"([^"]+)/);
  return match ? match[1] : null;
}
function anonymousReport() {
  const report = healthReport();
  const tools = new Map();
  for (const row of rows()) tools.set(row.tool, (tools.get(row.tool) || 0) + 1);
  return { schema: "skill-tracker-anonymous-report@1", generated_at: generatedAt(), source_generated_at: report.source_generated_at, privacy: { raw_logs: false, local_paths: false, sessions: false, skill_names: false }, totals: { rows: rows().length, skills: report.skills.length }, tools: [...tools.entries()].map(([tool, calls]) => ({ tool_id: stableId(tool), calls })).sort((a, b) => b.calls - a.calls), health: report.skills.map((item) => ({ skill_id: stableId(item.skill), calls: item.calls, tools: item.tools.map(stableId), health: item.health })) };
}
function stableId(value) { let hash = 2166136261; for (const char of String(value)) { hash ^= char.codePointAt(0); hash = Math.imul(hash, 16777619); } return `id-${(hash >>> 0).toString(16).padStart(8, "0")}`; }
function validateReport(value) { if (!value || value.schema !== "skill-tracker-anonymous-report@1") throw new Error("unsupported report schema"); if (!value.privacy || value.privacy.raw_logs || value.privacy.local_paths || value.privacy.sessions || value.privacy.skill_names) throw new Error("report contains disallowed private fields"); if (!Array.isArray(value.tools) || !Array.isArray(value.health)) throw new Error("invalid report shape"); return value; }
function output(value) { console.log(JSON.stringify(value, null, 2)); }
function shell() { return process.platform === "win32" ? "powershell" : "pwsh"; }

const command = args[0];
try {
  if (!command || command === "--help" || command === "-h") { usage(); process.exit(0); }
  if (command === "collect") process.exit(spawnSync(shell(), ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(root, "collect.ps1"), "-ForceScan"], { stdio: "inherit" }).status ?? 1);
  if (command === "open") process.exit(spawnSync(shell(), ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(root, "start-dashboard.ps1"), "-Server"], { stdio: "inherit" }).status ?? 1);
  if (command === "health") { output(healthReport()); process.exit(0); }
  if (command === "export") { const file = args[1]; if (!file) throw new Error("export requires FILE"); writeJson(path.resolve(file), anonymousReport()); console.log(`wrote ${path.resolve(file)}`); process.exit(0); }
  if (command === "import") { const value = validateReport(readJson(path.resolve(args[1]))); output({ schema: value.schema, source_generated_at: value.source_generated_at, totals: value.totals, tools: value.tools.length, health_rows: value.health.length }); process.exit(0); }
  if (command === "benchmark") { const dir = path.resolve(args[1] || "."); const reports = fs.readdirSync(dir).filter((name) => name.endsWith(".json")).map((name) => validateReport(readJson(path.join(dir, name)))); output({ schema: "skill-tracker-benchmark@1", generated_at: generatedAt(), reports: reports.map((value) => ({ source_generated_at: value.source_generated_at, totals: value.totals, tools: value.tools.length, health_rows: value.health.length })) }); process.exit(0); }
  throw new Error(`unknown command: ${command}`);
} catch (error) { console.error(`error: ${error.message}`); process.exit(1); }
