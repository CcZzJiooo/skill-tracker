import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const cli = path.join(root, "tools", "skill-tracker-cli.mjs");

function run(command) {
  const result = spawnSync(process.execPath, [cli, command], { cwd: root, encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return JSON.parse(result.stdout);
}

const discovery = run("tool-discovery");
assert.equal(discovery.schema, "skill-tracker-tool-discovery@1");
assert.equal(typeof discovery.available, "boolean");
assert.ok(Array.isArray(discovery.installed_tools));
assert.ok(Array.isArray(discovery.newly_detected_tools));
assert.ok(Array.isArray(discovery.removed_tools));
assert.ok(Array.isArray(discovery.unknown_candidates));
assert.equal(Object.hasOwn(discovery, "paths"), false);
assert.equal(Object.hasOwn(discovery, "log_roots"), false);

const health = run("health");
assert.deepEqual(health.tool_discovery, discovery);
assert.equal(Object.hasOwn(health.tool_discovery, "sources"), false);
assert.equal(Object.hasOwn(health.tool_discovery, "local_paths"), false);

const reportPath = path.join(root, "dashboard", "tool_report.json");
if (fs.existsSync(reportPath)) {
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8").replace(/^\uFEFF/, ""));
  assert.equal(discovery.generated_at, report.generated_at);
}

console.log("CLI adaptive tool discovery test passed.");
