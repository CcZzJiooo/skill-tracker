#!/usr/bin/env node
// Dependency-free, read-only MCP stdio server for local Skill Tracker reports.
import readline from "node:readline";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const cli = path.join(root, "tools", "skill-tracker-cli.mjs");
function callHealth() { const result = spawnSync(process.execPath, [cli, "health", "--json"], { encoding: "utf8" }); if (result.status !== 0) throw new Error(result.stderr || "health report failed"); return JSON.parse(result.stdout); }
function reply(id, result, error = null) { process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, ...(error ? { error: { code: -32000, message: error.message } } : { result }) }) + "\n"); }
const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  let request; try { request = JSON.parse(line); } catch { return; }
  try {
    if (request.method === "initialize") return reply(request.id, { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "skill-tracker", version: "0.4.0" } });
    if (request.method === "notifications/initialized") return;
    if (request.method === "tools/list") return reply(request.id, { tools: [{ name: "skill_health", description: "Read the local explainable skill health report. No raw logs, paths, or session IDs are returned.", inputSchema: { type: "object", properties: {} } }] });
    if (request.method === "tools/call" && request.params?.name === "skill_health") return reply(request.id, { content: [{ type: "text", text: JSON.stringify(callHealth(), null, 2) }] });
    return reply(request.id, {});
  } catch (error) { reply(request.id, null, error); }
});
