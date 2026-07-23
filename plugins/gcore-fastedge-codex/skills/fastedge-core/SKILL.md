---
name: fastedge-core
disable-model-invocation: true
description: Route FastEdge requests in Codex between docs retrieval and MCP-backed execution skills
---

# FastEdge Core (Codex)

## Purpose

Coordinate FastEdge workflows in Codex with strict separation:

- Local indexed docs for knowledge retrieval
- MCP tools for execution tasks

This core skill routes work to task skills that mirror Claude plugin behavior:

- `skills/scaffold/SKILL.md`
- `skills/deploy/SKILL.md`
- `skills/manage/SKILL.md`
- `skills/test/SKILL.md`
- `skills/debug/SKILL.md`
- `skills/live-test/SKILL.md`
- `skills/fastedge-docs/SKILL.md`

## Task Routing

Route user requests to specialized skills:

- New app/project creation -> `skills/scaffold/`
- Build/upload/deploy requests -> `skills/deploy/`
- App lifecycle/env/secrets/admin requests -> `skills/manage/`
- Automated test generation/execution -> `skills/test/`
- Manual scenario fixture/debug flows -> `skills/debug/`
- Verify deployed app against live edge traffic -> `skills/live-test/`
- Documentation/API/concept questions -> `skills/fastedge-docs/`

## Docs-first retrieval protocol

When asked FastEdge documentation/API questions:

1. Read `plugins/gcore-fastedge-codex/docs-index.json`
2. Select topic(s) by `id`, `tags`, `category`, `app_types`, `languages`
3. Read only relevant section ranges (`line_start`/`line_end`) from referenced markdown files
4. Answer with minimal context pull; avoid loading whole docs unless explicitly requested

Canonical docs roots:

- `plugins/gcore-fastedge-codex/skills/fastedge-docs/reference/`
- `plugins/gcore-fastedge-codex/skills/test/reference/`
- `plugins/gcore-fastedge-codex/skills/scaffold/reference/`

## Execution protocol

This plugin is the intelligence layer. Build, deploy, and manage execution runs through the **FastEdge MCP server** (the executor layer). The plugin is not standalone — without MCP, build/deploy/manage cannot run.

MCP-backed capabilities:

- Build: `build-wasm`
- Deploy: `upload-binary`, `gcore_api` (REST against `/fastedge/v1/apps` for create/update), `deployment-comments`
- Manage: `update-env-vars-app` (env/secrets merge), `gcore_api` (PUT for removals and uncovered ops), `get-secret-id`
- Live-test: `enable-app-http`, `attach-app-to-cdn-rule-create`, `attach-app-to-cdn-rule-update`, `gcore_api` (log queries)

## When MCP is not configured

If the MCP server is not available:

- Stop before any build/deploy/manage execution. State plainly that MCP is required and not yet configured.
- Do not fabricate tool execution results.
- Diagnose why the bundled MCP server didn't respond: Docker not running (`docker info`), or `GCORE_API_KEY` not visible to Codex (`echo $GCORE_API_KEY` — see README). The server ships with the plugin; do **not** tell the user to run `codex mcp add` (a manual entry would shadow the bundled server).
- Continue helping with local docs, scaffolding, tests, debug fixtures, and code edits — those don't depend on MCP.
- Local-toolchain commands are an explicit user opt-out, not a default. Surface them only if the user explicitly declines Docker, with a warning that the path is unsupported.
