# Gcore FastEdge — Cursor plugin

Cursor Marketplace build of the Gcore FastEdge plugin. Build, deploy, and manage
serverless WebAssembly apps on Gcore FastEdge (Wasm compute on 210+ global edge
PoPs) from inside Cursor.

This is the **third target** alongside the Claude Code (`gcore-fastedge`) and Codex
(`gcore-fastedge-codex`) plugins in this repo. It shares the same skills and the
same [FastEdge MCP server](https://github.com/G-Core/FastEdge-mcp-server); only the
manifest/packaging differs per CLI.

## Install from GitHub

Add this repository as a personal Cursor marketplace:

```bash
agent plugin marketplace add https://github.com/G-Core/fastedge-plugin.git
```

Then run `agent`, enter `/plugin`, open the **Marketplace** tab, and install
**Gcore FastEdge** at user or project scope.

The marketplace follows the repository's default branch. Pin a branch, tag, or
commit when testing a specific release:

```bash
agent plugin marketplace add \
  https://github.com/G-Core/fastedge-plugin.git \
  --git-ref main
```

Refresh or remove the marketplace with:

```bash
agent plugin marketplace update gcore-fastedge-marketplace
agent plugin marketplace remove gcore-fastedge-marketplace
```

Cursor Teams and Enterprise administrators can instead import the same repository
from **Dashboard → Plugins → Add Marketplace → Import from Repo**, then configure
the plugin as Default Off, Default On, or Required.

See the [Cursor quickstart](../../docs/cursor-quickstart.md) for prerequisites,
credentials, installation verification, and troubleshooting.

## Layout

```
.cursor-plugin/plugin.json   # Cursor manifest
mcp.json                     # FastEdge MCP server (Docker) — shared image
rules/fastedge-knowledge.mdc # Shared knowledge base, alwaysApply (generated from CLAUDE.md)
skills/                      # deploy, scaffold, manage, test, debug, live-test, fastedge-docs
```

**Generated files (do not hand-edit).** `rules/fastedge-knowledge.mdc` and every
`skills/*/SKILL.md` are produced from the Claude plugin sources by
`scripts/sync/generate-cursor-plugin.mjs` — a deterministic transform of
`CLAUDE.md` and the Claude `SKILL.md` files (adds Cursor frontmatter and rewrites
`CLAUDE.md`/`.mcp.json` cross-references). The `reference/` folders under `skills/`
are mirrored from the Claude plugin by `scripts/sync/mirror-reference.sh
gcore-fastedge-cursor`. All are `.gitignore`'d and committed via `git add --force`
by the release workflow, so the Cursor target can never silently drift from Claude.

## Design notes (manifest & credentials)

**Manifest is metadata-only, by convention.** `.cursor-plugin/plugin.json` carries
only descriptive metadata (name, version, author, keywords, …). Cursor discovers `skills/`,
`rules/*.mdc`, and `mcp.json` by their conventional directory locations — this is
Cursor's documented plugin layout, so the manifest intentionally does **not**
enumerate them (verified loading end-to-end). This differs from the Codex manifest,
which declares its pieces explicitly; it is a per-CLI convention, not an omission.

**Credential model — host env is forwarded (like Claude, unlike Codex).** Cursor
passes the host process environment through to the spawned MCP server, so
`mcp.json` forwards `GCORE_API_KEY` / `GCORE_API_BASE` **by name** with docker
`-e NAME` (no values committed) and needs **no** explicit declaration. This matches
the Claude plugin's `.mcp.json`. Codex is the exception — it sanitizes the child
environment, so its `.mcp.json` needs an `env_vars: [...]` list; Cursor has no such
requirement. Verified end-to-end on macOS and Windows (MCP server up, authenticated
API calls succeeded). The only wrinkle is getting the vars **into** Cursor's
environment in the first place — on macOS-GUI that means `launchctl setenv` (see
gotcha #1 below), not a missing manifest declaration.

## Local development

Generated skills, rules, reference files, and `docs-index.json` are committed in
release snapshots. Regenerate them after changing the Claude source files:

```bash
node scripts/sync/generate-cursor-plugin.mjs
bash scripts/sync/mirror-reference.sh gcore-fastedge-cursor
bash scripts/sync/generate-docs-index.sh
```

Load the working tree as a local plugin by symlinking (or copying) this folder into
`~/.cursor/plugins/local/`, then fully restart Cursor.

```bash
ln -sfn "$PWD/plugins/gcore-fastedge-cursor" ~/.cursor/plugins/local/gcore-fastedge-cursor
```

Docker must be running. Confirm the FastEdge skills load and the MCP server
`fastedge-assistant` starts — a `ghcr.io/g-core/fastedge-mcp-server` container
should appear in `docker ps` once a FastEdge tool is used.

### macOS gotchas (learned the hard way)

1. **The API key must reach Cursor's GUI process, not just your shell.**
   The committed `mcp.json` forwards `-e GCORE_API_KEY` **by name** from the
   parent environment — but a Cursor launched from the Dock/Finder does **not**
   see `export`s from your `.zshrc`. Two ways to supply it:

   - **Recommended (no secret in files)** — set it at the GUI-session level, then
     restart Cursor:
     ```bash
     launchctl setenv GCORE_API_KEY "your-api-key"
     launchctl setenv GCORE_API_BASE "https://api.gcore.com"
     ```
   - **Quick, local only** — in your **local copy** under
     `~/.cursor/plugins/local/`, inline the value in the args
     (`"-e", "GCORE_API_KEY=your-api-key"`). This puts the key in **plaintext** —
     never commit it, and keep the repo's `mcp.json` on the by-name passthrough form.

   Symptom if missing: the container starts, loads docs, then logs
   `GCORE_API_KEY is required` and closes with `MCP error -32000: Connection closed`.
   Note: only `GCORE_API_KEY` / `GCORE_API_BASE` are forwarded — `FASTEDGE_API_KEY`
   is **not**.

2. **MCP server-name collision.** This plugin names its server `fastedge-assistant`.
   If you also have a `fastedge-assistant` in a personal `~/.cursor/mcp.json`, one
   shadows the other (you'll see the wrong image running). Rename the personal one
   (e.g. `fastedge-assistant-dev`) while testing the plugin.

## Publishing

The GitHub marketplace installation above does not publish the plugin to Cursor's
official public marketplace. Official publication requires the public repository
to be submitted for review at https://cursor.com/marketplace/publish.
