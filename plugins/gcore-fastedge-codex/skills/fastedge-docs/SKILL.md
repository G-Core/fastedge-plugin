---
name: fastedge-docs
disable-model-invocation: false
description: FastEdge documentation and indexed local reference retrieval for Codex
---

# FastEdge Docs (Codex)

## Goal

Answer FastEdge questions with high precision and low token usage using local indexed docs.

## Inputs

- Index: `plugins/gcore-fastedge-codex/docs-index.json`
- Topic markdown: paths in each topic `path`

## Retrieval rules

- Always consult docs index before reading markdown.
- Prefer 1-3 section reads by line range.
- Use full-doc reads only if section-level data is insufficient.
- Prioritize topics with matching `tags`, `languages`, and `app_types`.
- Before proposing to hand-build a capability from scratch, check for a matching `templates`
  topic in the index first — it may already exist as a maintained, ready-to-deploy bolt-on
  installed from the Gcore portal, not something to scaffold.
- Before designing, writing, or reviewing a CDN app (proxy-wasm filter), read the
  `platform-cdn-filter-runtime` topic. Before designing anything that uses KV or Cache, read
  `platform-storage`. Both record host behaviour that local tests cannot reveal.

## Output rules

- Cite topic IDs used.
- Keep answer concise and implementation-oriented.
- If docs do not cover the question, explicitly say so and suggest the nearest topic IDs.
