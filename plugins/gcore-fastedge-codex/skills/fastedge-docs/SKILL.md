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

## Output rules

- Cite topic IDs used.
- Keep answer concise and implementation-oriented.
- If docs do not cover the question, explicitly say so and suggest the nearest topic IDs.
