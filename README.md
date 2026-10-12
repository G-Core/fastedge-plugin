# Gcore FastEdge Plugins

Build, deploy, and manage serverless WebAssembly applications on [Gcore FastEdge](https://gcore.com/fastedge) from Claude Code, Codex, or Cursor.

FastEdge runs Wasm workloads on 210+ global edge Points of Presence with sub-millisecond cold starts. The plugins in this repository let AI coding agents scaffold projects, deploy apps, and manage edge infrastructure through natural language.

## Claude Code Installation

**Option 1: Install from GitHub (recommended)**

From inside Claude Code, add the Gcore marketplace and install the plugin:

```
/plugin marketplace add G-Core/gcore-marketplace
/plugin install gcore-fastedge@gcore-marketplace
```

This persists across sessions. To pick up new versions later, run `/plugin marketplace update gcore-marketplace`.

**Option 2: Install from a local clone (for development or air-gapped use)**

Clone the repo first:

```bash
git clone https://github.com/G-Core/fastedge-plugin.git
```

Then either install persistently from the local path:

```
/plugin marketplace add /path/to/fastedge-plugin
/plugin install gcore-fastedge@gcore-fastedge-marketplace
```

Or load it for a single session by restarting Claude Code:

```bash
claude --plugin-dir /path/to/fastedge-plugin
```

## Codex Installation

**Option 1: Install from GitHub (recommended)**

```bash
codex plugin marketplace add G-Core/gcore-marketplace
codex plugin add gcore-fastedge@gcore-marketplace
```

**Option 2: Install from a local clone (for development or air-gapped use)**

Clone the repo (the same repository hosts all runtime targets):

```bash
git clone https://github.com/G-Core/fastedge-plugin.git
```

Add the Codex marketplace and install:

```bash
codex plugin marketplace add /path/to/fastedge-plugin
codex plugin add gcore-fastedge@gcore-fastedge-codex-marketplace
```

See [docs/codex-quickstart.md](docs/codex-quickstart.md) for full Codex setup details.

## Cursor Installation

Add this repository as a personal Cursor marketplace:

```bash
agent plugin marketplace add https://github.com/G-Core/fastedge-plugin.git
```

Then run `agent`, enter `/plugin`, open the **Marketplace** tab, and install
**Gcore FastEdge** at user or project scope. Cursor currently performs plugin
installation interactively; the CLI command above registers the marketplace.

To refresh or remove the marketplace later:

```bash
agent plugin marketplace update gcore-fastedge-marketplace
agent plugin marketplace remove gcore-fastedge-marketplace
```

See [docs/cursor-quickstart.md](docs/cursor-quickstart.md) for credential setup,
team marketplace installation, and troubleshooting.

---

## Setup

### Prerequisites

The plugins run build, deploy, and management operations through the [FastEdge MCP server](https://github.com/G-Core/FastEdge-mcp-server) — a Docker image that ships the toolchains (Rust, Node, wasm targets) and FastEdge API client. Installing a plugin auto-loads its bundled MCP configuration, which launches the server on demand.

You need:

- **Docker** running locally — required to start the MCP server.
- **Gcore API key** — set as `GCORE_API_KEY` (see below), or sign in through the portal instead (see [No API key?](#no-api-key-sign-in-through-the-portal)).

> Local-only mode (no Docker, no MCP) is available as an explicit opt-out for developers who prefer their own toolchain. See [Running without the MCP server](#running-without-the-mcp-server) below.

### Get a Gcore API key

1. Go to the [Gcore Portal](https://portal.gcore.com/)
2. Navigate to **Profile** → **API Keys** (or visit `portal.gcore.com/api-keys` directly)
3. Click **Create API Key**, give it a name, and copy the generated key
4. Give the key to the agent from **outside your project folder**: the MCP server mounts the project
   folder into its container, where your project's own build scripts (npm, cargo) can read every file
   in it. Either export it in the shell that starts the agent:

```bash
export GCORE_API_KEY="your-api-key"
```

or, for Claude Code, add it to your user settings, `~/.claude/settings.json`:

```json
{
  "env": {
    "GCORE_API_KEY": "your-api-key"
  }
}
```

Add `"GCORE_API_BASE"` only for a key from a non-prod environment.

Don't put a key in `.claude/settings.local.json`, a `.env` or a `.envrc` in the project: those files are
inside the mounted folder. Managing a key's security is up to you; portal sign-in (see
[No API key?](#no-api-key-sign-in-through-the-portal)) needs no key at all.

> **String literals only — no variable interpolation.**
>
> Values in an `env` block are passed through verbatim. Writing `"GCORE_API_KEY": "${MY_SECRET}"` will send the literal seven-character string `${MY_SECRET}` to the MCP server, not the value of `MY_SECRET`. The same applies to forms like `$MY_SECRET` or `~`.
>
> If you want the value to come from a shell variable rather than be written into the file, the shell variable must already be named `GCORE_API_KEY` or `GCORE_API_BASE` — and in that case, omit the `env` block entirely. The plugin's `.mcp.json` already passes `GCORE_API_KEY` and `GCORE_API_BASE` from the parent shell environment into the container, so an `export` is sufficient on its own.

### Credentials for Codex (host environment, not config)

Codex does **not** auto-load `.env` files, and — unlike Claude Code — you **cannot** pin credentials in `.codex/config.toml` for a plugin-provided MCP server. The bundled `.mcp.json` owns how the server launches (its transport), and Codex's config schema only lets user/project config set _policy_ for a plugin server (e.g. `enabled`, `startup_timeout_sec`, tool toggles), not transport keys like `env`. Adding an `env` block under `[plugins."…".mcp_servers.fastedge-assistant]` is rejected with `Additional properties are not allowed ('env' was unexpected)` and silently ignored.

Instead, credentials reach the server through the **host environment**. The bundled `.mcp.json` declares `env_vars = ["GCORE_API_KEY", "GCORE_API_BASE", "FASTEDGE_SESSION"]`, which tells Codex to forward those host variables into the server container. So set them in the shell you launch `codex` from:

```bash
export GCORE_API_KEY="your-api-key"
# export GCORE_API_BASE="https://api.preprod.world"   # only for a non-prod environment
codex
```

An `export` in your shell rc gives you a personal default across all projects.

> Whatever value is in the shell when you launch `codex` is the value forwarded to the server. If a stale `GCORE_API_KEY` is exported in your rc, it will shadow everything else — unset or fix it there.

### Credentials for Cursor on macOS

Cursor CLI inherits `GCORE_API_KEY` from the shell that launches it. The macOS
GUI does not normally inherit variables exported from `.zshrc`, so set the key
in the GUI session and restart Cursor:

```bash
launchctl setenv GCORE_API_KEY "your-api-key"
```

Set `GCORE_API_BASE` only for a non-prod environment, with a key from that environment. Leave it unset
otherwise: the server then uses prod, or the environment you saved when signing in through the portal.

The Cursor plugin forwards these variables by name to the MCP Docker container;
the key is not stored in the plugin or marketplace manifest.

### No API key? Sign in through the portal

**No API key?** Leave `GCORE_API_KEY` unset. The first API call then offers to sign you in through
the Gcore portal: you approve in your browser, and the MCP server gets a time-limited API token
(8 hours by default, 7 days at most). The server's token broker holds it; the agent never sees it.
The token is cached as plaintext in the `fastedge-session` Docker volume until it expires. Inside
the container only the token broker can read it, but anyone who can run Docker containers on this
machine can read it too. To keep this sign-in's token unusable on disk instead, choose **Only for
this MCP server session** on the page: the token is then encrypted to the running MCP server and you
approve again the next time it starts. A session saved earlier with "Keep me signed in" stays usable
until it expires or you sign out (`login --logout`). A key, when set, takes precedence. It can't be
combined with `FASTEDGE_SESSION=ephemeral`: the server then refuses to start.

In Codex, the sign-in runs a `docker run … login` command, which may need your approval to run outside the sandbox; if it can't run there, run the command it shows in your own terminal.

### Optional: preprod testing

Set `GCORE_API_BASE` (via any of the methods above) to override the API host (default: `https://api.gcore.com`; preprod: `https://api.preprod.world`). The MCP server appends `/fastedge/v1` itself. When set, it
also overrides the environment saved by portal sign-in (`login --set-default-origin`).

### Running without the MCP server

If you decline to run Docker, the deploy and manage skills can fall back to your local toolchain (`fastedge-build`, `cargo`, `asc`) and direct REST calls to `api.gcore.com`. This path is supported but not the default — you'll get a warning each session and you're responsible for keeping toolchains current.

## Available Skills

The three plugins share the same skill set but use different invocation styles:

| CLI             | Prefix             | Example                  |
| --------------- | ------------------ | ------------------------ |
| **Claude Code** | `/gcore-fastedge:` | `/gcore-fastedge:deploy` |
| **Codex**       | `$gcore-fastedge:` | `$gcore-fastedge:deploy` |
| **Cursor**      | `/`                | `/deploy`                |

| Skill         | Claude Code command                                                              | Description                                                                |
| ------------- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| **Scaffold**  | `/gcore-fastedge:scaffold [http\|cdn] [name] [description]`                      | Blueprint-driven project creation from SDK examples (HTTP and CDN)         |
| **Deploy**    | `/gcore-fastedge:deploy [app-name]`                                              | Build, test, and deploy a Wasm app to FastEdge via the MCP server          |
| **Manage**    | `/gcore-fastedge:manage [list\|get\|update\|delete\|secrets\|sync-env] [app-id]` | Inspect apps, manage secrets, and sync `.env` files to deployed apps       |
| **Test**      | `/gcore-fastedge:test`                                                           | Generate and run test suites using `@gcoredev/fastedge-test` (CI-friendly) |
| **Debug**     | `/gcore-fastedge:debug`                                                          | Generate scenario fixtures for the visual debugger                         |
| **Live-test** | `/gcore-fastedge:live-test`                                                      | Build, deploy, and run scenario fixtures against the live edge             |
| **Docs**      | Auto-invoked                                                                     | FastEdge platform docs, SDK reference, and best practices                  |

Replace `/gcore-fastedge:` with `$gcore-fastedge:` for Codex. In Cursor, invoke
the corresponding skill as `/scaffold`, `/deploy`, `/manage`, `/test`, `/debug`,
or `/live-test`, or ask the agent naturally.

## Example Usage

Ask your coding agent naturally:

- **"Scaffold a new HTTP app called my-api"** — creates a TypeScript project from SDK blueprints
- **"Deploy this app to FastEdge"** — builds the Wasm binary and deploys it to the edge
- **"List my FastEdge apps"** — shows all your deployed apps with status and URLs
- **"How does the FastEdge KV store work?"** — pulls up SDK reference docs inline

## Plugin Structure

```
fastedge-plugin/
├── .claude-plugin/
│   ├── marketplace.json              # Claude Code marketplace descriptor
│   └── plugin.json
├── .cursor-plugin/
│   └── marketplace.json              # Cursor marketplace descriptor
└── plugins/
    ├── gcore-fastedge/               # Claude Code plugin
    │   ├── .claude-plugin/plugin.json
    │   ├── .mcp.json                 # Launches the FastEdge MCP server (Docker)
    │   ├── CLAUDE.md                 # Shared knowledge base (API, SDK, auth, builds)
    │   ├── docs-index.json           # Pre-built docs search index
    │   └── skills/
    │       ├── scaffold/             # Blueprint-driven project scaffolding
    │       │   └── reference/        # http/ + cdn/ blueprints, build/init CLI guides
    │       ├── deploy/               # Build → upload binary → create/update app
    │       ├── manage/               # List/get/update/delete + secrets + sync-env
    │       ├── test/                 # Generate & run tests (@gcoredev/fastedge-test)
    │       ├── debug/                # Generate visual-debugger fixtures
    │       ├── live-test/            # Verify against the deployed edge
    │       └── fastedge-docs/        # Auto-invoked SDK / platform docs
    │           └── reference/        # http/, cdn/, platform/ + SDK references
    ├── gcore-fastedge-codex/         # Codex plugin (shares the same MCP server)
    │   ├── .codex-plugin/
    │   ├── .mcp.json
    │   ├── docs-index.json
    │   └── skills/
    └── gcore-fastedge-cursor/        # Cursor plugin
        ├── .cursor-plugin/plugin.json
        ├── mcp.json
        ├── docs-index.json
        ├── rules/
        └── skills/
```

## Links

- [Gcore FastEdge Documentation](https://gcore.com/docs/fastedge)
- [Gcore Portal](https://portal.gcore.com/)
- [FastEdge API Reference](https://api.gcore.com/docs/fastedge)
