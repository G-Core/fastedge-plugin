# Codex Quickstart

## What This Is

Use the Codex plugin at:

- `plugins/gcore-fastedge-codex`

This plugin pairs local docs with the FastEdge MCP server. Both layers are required for full functionality:

- **Reference docs** (intelligence layer): local index + markdown in this repo
- **Build/deploy/manage** (executor layer): FastEdge MCP server tools — Docker image `ghcr.io/g-core/fastedge-mcp-server:latest`

The plugin is not standalone. Without the MCP server, only docs Q&A works.

Codex marketplace descriptor in this repo:

- `.agents/plugins/marketplace.json`

## Prerequisites

- Codex CLI installed
- Docker installed
- `GCORE_API_KEY` set in your shell environment

## Install the plugin

```bash
codex plugin marketplace add G-Core/gcore-marketplace
codex plugin add gcore-fastedge@gcore-marketplace
```

This persists across sessions. For a local-clone or air-gapped install, see the [README](../README.md#codex-installation).

## MCP Server (bundled — no manual setup)

Installing the plugin auto-loads its bundled `.mcp.json`, which launches the FastEdge MCP server (Docker image `ghcr.io/g-core/fastedge-mcp-server:latest`) on demand. You do **not** need to run `codex mcp add` — and you shouldn't: a manual entry would shadow the plugin's bundled server.

You only need:

- Docker running locally
- `GCORE_API_KEY` available to Codex — **exported in your shell** before launching `codex` (the bundled `.mcp.json` forwards it via `env_vars`). Codex can't pin credentials per-project in `.codex/config.toml` for a plugin server, so per-project keys come from the shell environment (e.g. via `direnv`). See the README section "Credentials for Codex".

Verify Codex sees the bundled server:

```bash
codex mcp get fastedge-assistant
```

It should show `command: sh … docker run …` and `env: GCORE_API_KEY=*****`. Then launch `codex` normally and run `/mcp` to confirm the tools are listed.

## Plugin Metadata Location

Codex plugin files:

- `plugins/gcore-fastedge-codex/.codex-plugin/plugin.json`
- `plugins/gcore-fastedge-codex/skills/`
- `plugins/gcore-fastedge-codex/.mcp.json`

## Skill Coverage

Codex plugin skill set now includes:

- `skills/fastedge-core/` (global routing/policy)
- `skills/fastedge-docs/` (indexed docs retrieval)
- `skills/scaffold/` (project scaffolding)
- `skills/deploy/` (build/upload/deploy)
- `skills/manage/` (app/env/secrets lifecycle)
- `skills/test/` (test generation/execution)
- `skills/debug/` (local debug fixtures)

## Docs Retrieval Behavior

Codex plugin reads from its own vendored docs (mirrored from the Claude plugin at each release):

- `plugins/gcore-fastedge-codex/docs-index.json`
- `plugins/gcore-fastedge-codex/skills/fastedge-docs/reference/*.md`
- `plugins/gcore-fastedge-codex/skills/test/reference/*.md`

It should resolve topics via `docs-index.json` first, then read only target section ranges.

## When MCP Is Not Configured

The MCP server is the executor — without it, build/deploy/manage skills cannot run. If a user attempts these skills before configuring MCP, the plugin should:

- Continue answering docs Q&A from local indexed docs
- Stop before any build/deploy/manage action and explain the likely cause — Docker not running, or `GCORE_API_KEY` not available to Codex (see README "Credentials for Codex") — rather than claiming success
- Not claim deployment/build success
