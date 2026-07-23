# Quickstart

## Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- **Docker** running locally — the plugin runs build/deploy/manage through the FastEdge MCP server (a Docker image). The plugin's bundled `.mcp.json` starts it on demand.
- Gcore account with FastEdge access
- Gcore API token (from [Gcore portal](https://accounts.gcore.com/profile/api-tokens)) exported as `GCORE_API_KEY`

> Developers who decline to run Docker can use the local-toolchain opt-out path described in the top-level [README](../README.md#running-without-the-mcp-server). The default install assumes Docker.

## Install the Plugin

From inside Claude Code, add the marketplace from GitHub and install:

```
/plugin marketplace add G-Core/fastedge-plugin
/plugin install gcore-fastedge@gcore-fastedge-marketplace
```

This persists across sessions. For a local-clone or air-gapped install, see the [README](../README.md#installation).

## Create Your First App

```
/gcore-fastedge:scaffold
```

The scaffold skill will ask you for:
1. App type (CDN or HTTP)
2. Language (JavaScript, TypeScript, Rust, or AssemblyScript)
3. Project name

It selects the right blueprint for your app type and language, then creates a project with working code, dependencies, and build config.

## Write Tests

```
/gcore-fastedge:test
```

Generates a test suite using `@gcoredev/fastedge-test` and creates `test-config.json` for the VSCode debugger.

## Deploy

```
/gcore-fastedge:deploy
```

Builds your app to WASM, uploads the binary, and creates or updates the FastEdge app via the Gcore API.

## Manage Apps

```
/gcore-fastedge:manage list
/gcore-fastedge:manage get <app-id>
/gcore-fastedge:manage secrets
```

## Troubleshooting

- **"Permission denied"**: Make sure your Gcore API token is set. The deploy skill will prompt you.
- **MCP server not starting**: Verify Docker is running (`docker ps`). The plugin pulls `ghcr.io/g-core/fastedge-mcp-server:latest` on first use; check network access to `ghcr.io`.
- **Build fails (MCP path)**: Check the MCP server logs (`/mcp` inside Claude Code shows server status). Most build issues are reported back through the tool response.
- **Build fails (local opt-out path)**: You're outside the supported default — make sure your local toolchain is installed (`fastedge-build` for JS/TS, `cargo` for Rust, `asc` for AssemblyScript).
- **Plugin not loading**: Run `/plugin marketplace list` to confirm the marketplace was added, then `/plugin install gcore-fastedge@gcore-fastedge-marketplace`. (For a local `--plugin-dir` install, ensure the path points to the directory containing `.claude-plugin/marketplace.json`.)
