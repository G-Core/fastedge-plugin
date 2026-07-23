#!/usr/bin/env node
// generate-cursor-plugin.mjs — Generate the Cursor plugin's derived files from
// the Claude plugin sources. Deterministic: same inputs -> identical output.
//
// Produces (overwrites):
//   plugins/gcore-fastedge-cursor/rules/fastedge-knowledge.mdc   (from CLAUDE.md)
//   plugins/gcore-fastedge-cursor/skills/<skill>/SKILL.md        (from Claude SKILL.md)
//
// The Cursor SKILL.md and rule file are a mechanical transform of the Claude
// sources (three deterministic edits — see below). Generating them keeps the
// Cursor target from silently drifting when a Claude SKILL.md or CLAUDE.md
// changes: it can't, because these are never hand-edited.
//
// These are generated artifacts: .gitignore'd and committed via `git add --force`
// by release-plugin.yml (same pattern as the mirrored reference/ folders and
// docs-index.json). Do not hand-edit — changes are overwritten on every release.
//
// Run in release-plugin.yml BEFORE mirror-reference.sh (on a clean checkout
// this script is what creates the skills/<skill>/ dirs the mirror copies into)
// and BEFORE generate-docs-index.sh (docs-index reads the generated skills).

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const pluginRoot = path.resolve(scriptDir, "../..");

const CLAUDE_DIR = path.join(pluginRoot, "plugins/gcore-fastedge");
const CURSOR_DIR = path.join(pluginRoot, "plugins/gcore-fastedge-cursor");

// The Cursor knowledge-base rule carries this frontmatter; the body is CLAUDE.md
// verbatim (after the shared substitutions below). Cursor loads a .mdc rule with
// `alwaysApply: true` as persistent context — the equivalent of Claude's CLAUDE.md.
const RULE_FRONTMATTER =
  "---\n" +
  "description: FastEdge platform knowledge — API, SDKs, auth, build/deploy. Shared context for all FastEdge skills.\n" +
  "alwaysApply: true\n" +
  "---\n\n";

// Deterministic edits applied to every derived file so the Cursor copies point at
// Cursor paths instead of Claude ones. Plain string replacement (not regex) — the
// tokens contain dots/slashes but no regex metacharacters we want interpreted.
function applySubstitutions(text) {
  return text
    .split("plugins/gcore-fastedge/CLAUDE.md")
    .join("rules/fastedge-knowledge.mdc")
    .split(".mcp.json")
    .join("mcp.json");
}

// SKILL.md gains an explicit `name:` line as the first frontmatter key. Claude
// infers the skill name from the directory; Cursor wants it declared.
function insertName(text, skill) {
  if (!text.startsWith("---\n")) {
    throw new Error(`SKILL.md for '${skill}' does not start with '---' frontmatter`);
  }
  return "---\n" + `name: ${skill}\n` + text.slice("---\n".length);
}

function writeIfChanged(dest, contents) {
  const prev = fs.existsSync(dest) ? fs.readFileSync(dest, "utf8") : null;
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, contents);
  return prev !== contents;
}

// --- Rule file: CLAUDE.md -> rules/fastedge-knowledge.mdc -------------------
const claudeMd = fs.readFileSync(path.join(CLAUDE_DIR, "CLAUDE.md"), "utf8");
const mdcPath = path.join(CURSOR_DIR, "rules/fastedge-knowledge.mdc");
const mdcChanged = writeIfChanged(mdcPath, RULE_FRONTMATTER + applySubstitutions(claudeMd));
console.log(`${mdcChanged ? "updated" : "unchanged"} rules/fastedge-knowledge.mdc`);

// --- Skills: Claude SKILL.md -> Cursor SKILL.md -----------------------------
const skillsSrc = path.join(CLAUDE_DIR, "skills");
const skills = fs
  .readdirSync(skillsSrc)
  .filter(
    (d) =>
      fs.statSync(path.join(skillsSrc, d)).isDirectory() &&
      fs.existsSync(path.join(skillsSrc, d, "SKILL.md")),
  )
  .sort();

for (const skill of skills) {
  const src = fs.readFileSync(path.join(skillsSrc, skill, "SKILL.md"), "utf8");
  const out = applySubstitutions(insertName(src, skill));
  const dest = path.join(CURSOR_DIR, "skills", skill, "SKILL.md");
  const changed = writeIfChanged(dest, out);
  console.log(`${changed ? "updated" : "unchanged"} skills/${skill}/SKILL.md`);
}

// Remove Cursor skill dirs whose Claude source is gone (stale after an upstream
// rename/removal) — keeps output independent of prior runs in a dirty tree.
const skillsDst = path.join(CURSOR_DIR, "skills");
for (const entry of fs.readdirSync(skillsDst, { withFileTypes: true })) {
  if (entry.isDirectory() && !skills.includes(entry.name)) {
    fs.rmSync(path.join(skillsDst, entry.name), { recursive: true });
    console.log(`removed stale skills/${entry.name}`);
  }
}
