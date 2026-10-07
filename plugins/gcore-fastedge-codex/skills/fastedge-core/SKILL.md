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
- Manage: `gcore_api` (GET/PATCH/PUT/DELETE on `/fastedge/v1/apps`, `/fastedge/v1/secrets`, `/fastedge/v1/stats/*`)
- Live-test: `enable-app-http`, `attach-app-to-cdn-rule-create`, `attach-app-to-cdn-rule-update`, `gcore_api` (log queries)

## Not signed in (`auth_required`)

The MCP server holds the credential: `GCORE_API_KEY` from the config, or a portal sign-in session when no key is set. Don't check the key in the shell. When an MCP call returns `auth_required`, follow the instructions in that result:

- It offers sign-in choices; ask the user which one. Never ask them to paste a token or connect code into the chat.
- The login is a `docker run … login` command. It talks to the Docker daemon, so it may need approval to run outside the sandbox. If it can't run, ask the user to run it in their own terminal on the same machine.
- The command prints a portal URL and then waits for approval. Show the user the URL as soon as it appears; don't wait for the command to finish.
- After a successful login, retry the request. No restart is needed for the same account.
- `account_changed` means another account replaced the session. Codex can't restart one MCP server: the user exits and runs `codex resume --last`. Don't retry.
- More (the "Keep me signed in" choice, enforcing "don't keep" with `FASTEDGE_SESSION=ephemeral`, every `auth_required` reason): the `platform-sign-in` docs topic.

## When MCP is not configured

If the MCP server is not available:

- Stop before any build/deploy/manage execution. State plainly that MCP is required and not yet configured.
- Do not fabricate tool execution results.
- Diagnose why the bundled MCP server didn't respond: Docker not running (`docker info`), or the plugin config is stale (`codex mcp get fastedge-assistant`). Never print `GCORE_API_KEY` (e.g. `echo $GCORE_API_KEY`): it would put a real key in the transcript. The server ships with the plugin; do **not** tell the user to run `codex mcp add` (a manual entry would shadow the bundled server).
- Continue helping with local docs, scaffolding, tests, debug fixtures, and code edits — those don't depend on MCP.
- Local-toolchain commands are an explicit user opt-out, not a default. Surface them only if the user explicitly declines Docker, with a warning that the path is unsupported.
