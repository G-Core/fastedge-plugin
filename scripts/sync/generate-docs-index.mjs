#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const schemaVersion = "1.0.0";
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const pluginRoot = path.resolve(scriptDir, "../..");

const args = process.argv.slice(2);
const pluginDirIdx = args.indexOf("--plugin-dir");
if (pluginDirIdx >= 0 && (pluginDirIdx + 1 >= args.length || args[pluginDirIdx + 1].startsWith("--"))) {
  console.error("Error: --plugin-dir requires a value (e.g. --plugin-dir gcore-fastedge)");
  process.exit(1);
}
const pluginDir = pluginDirIdx >= 0 ? args[pluginDirIdx + 1] : "gcore-fastedge";

const outputPath = path.join(pluginRoot, `plugins/${pluginDir}/docs-index.json`);

// Indexed skill list comes from reference-skills.json (.indexed).
const { indexed } = JSON.parse(
  fs.readFileSync(path.join(scriptDir, "reference-skills.json"), "utf8"),
);
const referenceRoots = indexed.map((skill) =>
  path.join(pluginRoot, `plugins/${pluginDir}/skills/${skill}/reference`),
);

const stopWords = new Set([
  "the","a","an","is","are","was","were","be","been","being","have","has","had","do","does","did",
  "will","would","could","should","may","might","must","shall","can","need","to","of","in","for","on",
  "with","at","by","from","as","into","through","during","before","after","above","below","between","and",
  "but","or","not","no","nor","so","yet","both","either","neither","each","every","all","any","few",
  "more","most","other","some","such","than","too","very","just","also","this","that","these","those",
  "it","its","if","then","else","when","where","how","what","which","who","whom","why",
]);

function toPosixRelative(absPath) {
  const rel = path.relative(pluginRoot, absPath);
  return rel.split(path.sep).join("/");
}

function slugify(input) {
  return input
    .toLowerCase()
    .replace(/[`'"().,:!?/\\]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

function extractKeywords(text) {
  const sample = text.slice(0, 500).toLowerCase();
  const words = sample
    .split(/[^a-z0-9_.-]+/)
    .filter((w) => w.length > 2 && !stopWords.has(w));
  return [...new Set(words)].slice(0, 40);
}

function detectCategory(id, relPath, skill) {
  if (skill === "test") return "testing";
  if (id.startsWith("sdk-reference") || id === "host-services-rust") return "sdk";
  if (relPath.includes("/platform/") || id === "quickstart" || id === "js-runtime") return "platform";
  if (relPath.includes("/http/") || relPath.includes("/cdn/") || id.startsWith("examples-")) return "examples";
  return "reference";
}

function detectLanguages(id, content) {
  const langs = new Set();
  const hay = `${id} ${content.slice(0, 1200)}`.toLowerCase();
  if (hay.includes("javascript") || id.includes("-js")) langs.add("javascript");
  if (hay.includes("typescript") || id.includes("-ts")) langs.add("typescript");
  if (hay.includes("rust") || id.includes("-rust")) langs.add("rust");
  if (hay.includes("assemblyscript") || id.includes("-as")) langs.add("assemblyscript");
  return [...langs];
}

function detectAppTypes(relPath) {
  const appTypes = [];
  if (relPath.includes("/http/")) appTypes.push("http");
  if (relPath.includes("/cdn/")) appTypes.push("cdn");
  return appTypes;
}

function extractTitle(content, fallback) {
  const m = content.match(/^#\s+(.+)$/m);
  return m ? m[1].trim() : fallback;
}

function extractDescription(content) {
  const lines = content.split("\n");
  let description = "";
  let started = false;
  let inFence = false;
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith("```")) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    if (!started && trimmed && !trimmed.startsWith("#") && !trimmed.startsWith("<!--") && !trimmed.startsWith("-") && !trimmed.startsWith("|")) {
      started = true;
      description = trimmed;
      continue;
    }
    if (started && !trimmed) break;
    if (started) description += ` ${trimmed}`;
  }
  return description.slice(0, 280);
}

function parseSections(id, content) {
  const lines = content.split("\n");
  const headingCandidates = lines
    .map((line, idx) => ({ line, idx: idx + 1 }))
    .filter(({ line }) => /^##\s+/.test(line) || /^###\s+/.test(line));

  const hasH2 = headingCandidates.some(({ line }) => /^##\s+/.test(line));
  const acceptedLevel = hasH2 ? 2 : 3;

  const headings = headingCandidates
    .map(({ line, idx }) => {
      const m = line.match(/^(##|###)\s+(.+)$/);
      if (!m) return null;
      const level = m[1] === "##" ? 2 : 3;
      if (level !== acceptedLevel) return null;
      return { level, heading: m[2].trim(), lineStart: idx };
    })
    .filter(Boolean);

  const sections = [];

  if (headings.length === 0) {
    const body = content.trim();
    if (body) {
      sections.push({
        id: `${id}#introduction`,
        heading: "Introduction",
        level: 1,
        anchor: "introduction",
        line_start: 1,
        line_end: lines.length,
        keywords: extractKeywords(body),
      });
    }
    return sections;
  }

  const introLineEnd = headings[0].lineStart - 1;
  const introText = lines.slice(0, introLineEnd).join("\n").trim();
  if (introText) {
    sections.push({
      id: `${id}#introduction`,
      heading: "Introduction",
      level: 1,
      anchor: "introduction",
      line_start: 1,
      line_end: introLineEnd,
      keywords: extractKeywords(introText),
    });
  }

  for (let i = 0; i < headings.length; i++) {
    const curr = headings[i];
    const next = headings[i + 1];
    const lineEnd = next ? next.lineStart - 1 : lines.length;
    const sectionText = lines.slice(curr.lineStart - 1, lineEnd).join("\n");
    const anchor = slugify(curr.heading);
    sections.push({
      id: `${id}#${anchor}`,
      heading: curr.heading,
      level: curr.level,
      anchor,
      line_start: curr.lineStart,
      line_end: lineEnd,
      keywords: extractKeywords(sectionText),
    });
  }

  return sections;
}

function topicTags({ category, skill, appTypes, languages, sections }) {
  const sKeywords = sections.flatMap((s) => s.keywords).slice(0, 20);
  const tags = new Set([category, skill, ...appTypes, ...languages, ...sKeywords]);
  return [...tags].filter(Boolean).slice(0, 48);
}

function hashContent(content) {
  return crypto.createHash("sha256").update(content, "utf8").digest("hex");
}

function walkMdFiles(rootDir) {
  const out = [];
  function walk(dir) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(abs);
      else if (entry.isFile() && entry.name.endsWith(".md")) out.push(abs);
    }
  }
  if (fs.existsSync(rootDir)) walk(rootDir);
  return out;
}

function detectSkill(relPath) {
  const parts = relPath.split("/");
  const i = parts.indexOf("skills");
  if (i >= 0 && parts[i + 1]) return parts[i + 1];
  return "unknown";
}

function getSourceCommit() {
  try {
    return execSync("git rev-parse --short HEAD", { cwd: pluginRoot, stdio: ["ignore", "pipe", "ignore"] })
      .toString()
      .trim();
  } catch {
    return "unknown";
  }
}

const topics = [];
const idSet = new Set();

function deriveTopicId(relPath) {
  const segments = relPath.split("/");
  const refIdx = segments.lastIndexOf("reference");
  if (refIdx < 0 || refIdx === segments.length - 1) {
    return path.basename(relPath, ".md");
  }
  const subPath = segments.slice(refIdx + 1);
  subPath[subPath.length - 1] = subPath[subPath.length - 1].replace(/\.md$/, "");
  return subPath.join("-");
}

for (const root of referenceRoots) {
  for (const absPath of walkMdFiles(root)) {
    const relPath = toPosixRelative(absPath);
    const id = deriveTopicId(relPath);

    if (idSet.has(id)) {
      console.error(`Duplicate topic id detected: ${id} (${relPath})`);
      process.exit(1);
    }
    idSet.add(id);

    const content = fs.readFileSync(absPath, "utf8");
    const skill = detectSkill(relPath);
    const sections = parseSections(id, content);
    const category = detectCategory(id, relPath, skill);
    const appTypes = detectAppTypes(relPath);
    const languages = detectLanguages(id, content);

    const topic = {
      id,
      title: extractTitle(content, id),
      description: extractDescription(content),
      path: relPath,
      skill,
      category,
      app_types: appTypes,
      languages,
      tags: topicTags({ category, skill, appTypes, languages, sections }),
      content_sha256: hashContent(content),
      sections,
    };

    topics.push(topic);
  }
}

topics.sort((a, b) => a.id.localeCompare(b.id));

const payload = {
  schema_version: schemaVersion,
  generated_at: new Date().toISOString(),
  source: {
    repo: "fastedge-plugin",
    commit: getSourceCommit(),
    pipeline: "sync-reference-docs",
  },
  topics,
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, JSON.stringify(payload, null, 2) + "\n", "utf8");

console.log(`Generated docs index: ${path.relative(pluginRoot, outputPath)} (${topics.length} topics)`);
