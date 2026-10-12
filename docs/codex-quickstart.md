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
- `GCORE_API_KEY` set in your shell environment, or none: sign in through the portal on first use
  (see "No API key?" below)

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
- With an API key: `GCORE_API_KEY` available to Codex — **exported in your shell** before launching `codex` (the bundled `.mcp.json` forwards it via `env_vars`). Codex can't pin credentials per-project in `.codex/config.toml` for a plugin server, so a key comes from the shell environment. Keep it out of files inside the project (such as a `direnv` `.envrc`): the project folder is mounted into the MCP container, where build scripts can read it. See the README section "Credentials for Codex".

Verify Codex sees the bundled server:

```bash
codex mcp get fastedge-assistant
```

It should show `command: sh … docker run …` and `env: GCORE_API_KEY=*****`. Then launch `codex` normally and run `/mcp` to confirm the tools are listed.

**No API key?** Leave `GCORE_API_KEY` unset. The first API call then offers to sign you in through
the Gcore portal: you approve in your browser, and the MCP server gets a time-limited API token
(8 hours by default, 7 days at most). The server's token broker holds it; the agent never sees it.
The token is cached as plaintext in the `fastedge-session` Docker volume until it expires. Inside
the container only the token broker can read it, but anyone who can run Docker containers on this
machine can read it too. To keep this sign-in's token unusable on disk instead, choose **Only for
this MCP server session** on the page: the token is then encrypted to the running MCP server and you
approve again the next time it starts. A session saved earlier with "Keep me signed in" stays usable
until it expires or you sign out (`login --logout`). A key, when set, takes precedence. It can't be
combined with `FASTEDGE_SESSION=ephemeral`: the server then refuses to start. The sign-in runs a `docker run … login` command, which may need your approval to run outside the sandbox; if it can't run there, run the command Codex shows in your own terminal. To switch accounts later, exit and run `codex resume --last` (Codex can't restart one MCP server).

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
- Stop before any build/deploy/manage action and explain the likely cause — Docker not running, or a stale
  plugin config (`codex mcp get fastedge-assistant`) — rather than claiming success. A missing `GCORE_API_KEY` is
  not a cause: without one, API tools offer portal sign-in.
- Not claim deployment/build success
