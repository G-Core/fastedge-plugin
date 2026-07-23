#!/usr/bin/env node
// Rewrite docs-index.json topic path fields to be relative to an artifact root.
//
// Usage:
//   node rewrite-docs-index-paths.mjs \
//     --input  plugins/gcore-fastedge/docs-index.json \
//     --output dist/stage/.../docs-index.json \
//     --prefix reference
//
// Transforms each topic.path:
//   plugins/gcore-fastedge/skills/<skill>/reference/<rest>
//   → <prefix>/<skill>/<rest>
import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
function arg(flag) {
  const i = args.indexOf(flag);
  if (i < 0 || !args[i + 1]) {
    console.error(`Missing required argument: ${flag}`);
    process.exit(1);
  }
  return args[i + 1];
}

const inputPath = arg("--input");
const outputPath = arg("--output");
const prefix = arg("--prefix");

const index = JSON.parse(fs.readFileSync(inputPath, "utf8"));

const SKILL_PATH_RE = /^plugins\/gcore-fastedge\/skills\/([^/]+)\/reference\/(.+)$/;

for (const topic of index.topics) {
  const m = topic.path.match(SKILL_PATH_RE);
  if (m) {
    topic.path = `${prefix}/${m[1]}/${m[2]}`;
  }
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, JSON.stringify(index, null, 2) + "\n", "utf8");
console.log(`Rewrote ${index.topics.length} topic paths → ${outputPath}`);
