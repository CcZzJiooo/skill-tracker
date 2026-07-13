const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const html = fs.readFileSync("dashboard/index.html", "utf8");
const functionName = "normalizeGitHubDescription";
const functionStart = html.indexOf(`function ${functionName}(`);

assert.notEqual(functionStart, -1, "GitHub descriptions need a normalizer before rendering.");

const bodyStart = html.indexOf("{", functionStart);
let depth = 0;
let functionEnd = -1;
for (let index = bodyStart; index < html.length; index += 1) {
  if (html[index] === "{") depth += 1;
  if (html[index] === "}") depth -= 1;
  if (depth === 0) {
    functionEnd = index + 1;
    break;
  }
}

assert.notEqual(functionEnd, -1, "GitHub description normalizer has an incomplete body.");

const context = {};
vm.createContext(context);
vm.runInContext(html.slice(functionStart, functionEnd), context);

const longDescription = "A repository description " + "x".repeat(11090);
const normalized = context[functionName](longDescription, 240);
assert.ok(normalized.length <= 240, "GitHub descriptions must be capped before rendering or translation.");
assert.equal(/\s/.test(normalized), true, "Normalized descriptions should preserve readable word separation.");
assert.equal(normalized.includes("\n"), false, "Normalized descriptions should not contain layout-breaking newlines.");

const filterName = "isGitHubRepositoryDescriptionUsable";
const filterStart = html.indexOf(`function ${filterName}(`);
assert.notEqual(filterStart, -1, "GitHub search needs to reject suspiciously oversized descriptions.");
const filterBodyStart = html.indexOf("{", filterStart);
depth = 0;
let filterEnd = -1;
for (let index = filterBodyStart; index < html.length; index += 1) {
  if (html[index] === "{") depth += 1;
  if (html[index] === "}") depth -= 1;
  if (depth === 0) {
    filterEnd = index + 1;
    break;
  }
}
assert.notEqual(filterEnd, -1, "GitHub description filter has an incomplete body.");
vm.runInContext(html.slice(filterStart, filterEnd), context);
assert.equal(context[filterName](longDescription), false, "Oversized GitHub descriptions should be removed before cards are rendered.");
assert.equal(context[filterName]("A normal repository description."), true, "Normal GitHub descriptions should remain searchable.");

assert.match(html, /\.repo-description\s*\{[\s\S]*?-webkit-line-clamp:\s*4/, "GitHub description cards need a visual line clamp.");
assert.match(html, /function renderGitHubProjects[\s\S]*?normalizeGitHubDescription\(/, "GitHub renderer must use the normalizer.");
assert.match(html, /class="repo-meta repo-description"/, "GitHub description markup must opt into the compact card style.");

console.log("GitHub result formatting test passed.");
