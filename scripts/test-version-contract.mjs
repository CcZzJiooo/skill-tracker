#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const expected = "0.5.1";
const version = fs.readFileSync(path.join(root, "VERSION"), "utf8").trim();
assert.equal(version, expected, "VERSION must identify the 0.5.1 release");

const cli = spawnSync(process.execPath, [path.join(root, "tools", "skill-tracker-cli.mjs"), "--version"], { encoding: "utf8" });
assert.equal(cli.status, 0, cli.stderr);
assert.equal(cli.stdout.trim(), expected, "CLI version must match VERSION");

const initialize = JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: {} }) + "\n";
const mcp = spawnSync(process.execPath, [path.join(root, "tools", "mcp-server.mjs")], { input: initialize, encoding: "utf8" });
assert.equal(mcp.status, 0, mcp.stderr);
const response = JSON.parse(mcp.stdout.trim());
assert.equal(response.result.serverInfo.version, expected, "MCP version must match VERSION");

const citation = fs.readFileSync(path.join(root, "CITATION.cff"), "utf8");
assert.match(citation, /^version: "0\.5\.1"$/m, "CITATION.cff version must match VERSION");

console.log("Version contract passed.");
