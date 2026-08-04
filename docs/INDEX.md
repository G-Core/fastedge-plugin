# fastedge-plugin Documentation

## What This Is

AI plugin repository for Gcore FastEdge.

- Claude plugin: `plugins/gcore-fastedge`
- Codex plugin: `plugins/gcore-fastedge-codex`
- Cursor plugin: `plugins/gcore-fastedge-cursor`

## Documentation

| Document | Audience | Description |
|----------|----------|-------------|
| [Quickstart](quickstart.md) | Claude users | Install Claude plugin and run first skills |
| [Codex Quickstart](codex-quickstart.md) | Codex users | Configure Codex MCP + local indexed docs flow |
| [Cursor Quickstart](cursor-quickstart.md) | Cursor users | Install the GitHub marketplace and configure credentials |
| [README](../README.md) | Users | Main plugin overview |
| [CLAUDE.md](../CLAUDE.md) | Developers | Repository structure and maintenance guide |
| [Context Index](../context/CONTEXT_INDEX.md) | Developers | Discovery guide for context docs |

## Architecture

Reference docs are generated in `plugins/gcore-fastedge/skills/*/reference/` and indexed in:

- `plugins/gcore-fastedge/docs-index.json`

This is the single source of truth consumed by Claude plugin, Codex plugin, and MCP server sync.

Marketplace metadata lives at:

- `.agents/plugins/marketplace.json`
- `.cursor-plugin/marketplace.json`
