---
disable-model-invocation: false
argument-hint: "[list|get|update|delete|secrets|sync-env] [app-id] [--from <dir>] [--auto-apply]"
description: List, get, update, or delete FastEdge apps, manage secrets, and sync dotenv files
---

# Manage FastEdge Apps

Manage your deployed FastEdge applications.

## MCP Server Integration

This skill runs API operations through the **FastEdge MCP server** (the executor layer). The plugin's bundled `.mcp.json` launches `ghcr.io/g-core/fastedge-mcp-server:latest` automatically; this is the default path.

For covered operations, run the MCP tool. For operations the MCP server doesn't expose yet (delete app, list secrets, app stats), make direct API calls — that's a coverage gap, not a fallback choice.

If MCP tool calls fail, diagnose first (Docker running? API key forwarded? Network?). Only drop to direct API for the whole skill if the user explicitly chooses to skip MCP — warn them they're outside the supported default. See `/gcore-fastedge:deploy` for the canonical MCP config.

### MCP Coverage

| Operation | MCP Tool | Status |
|-----------|----------|--------|
| List apps | `update-or-create-app` (with appName search) | Partial — no list-all tool, direct API used for full list |
| Get app | `update-or-create-app` (with appId) | ✓ Covered |
| Update app config | `update-or-create-app` | ✓ Covered |
| Update env/secrets/headers | `update-env-vars-app` | ✓ Covered |
| Delete app | — | Gap — direct API |
| List secrets | — | Gap — direct API |
| Get secret ID | `get-secret-id` | ✓ Covered |
| App stats | — | Gap — direct API |

---

## Instructions

Parse the user's arguments to determine the subcommand:
- `list` — List all apps
- `get <id>` — Get details for a specific app
- `update <id>` — Update an app's configuration
- `delete <id>` — Delete an app (with confirmation)
- `secrets list` — List all secrets
- `secrets get <name>` — Get secret ID by name
- `sync-env <id-or-name> [--from <dir>] [--auto-apply]` — Sync dotenv files to a deployed app. Defaults to project root; pass `--from` to read from a specific directory like `fixtures/` or `fixtures/germany/`. Tiered confirmation: additive diffs (adds and value changes) auto-apply; destructive diffs (keys on the deployed app not in `.env*`) prompt with default-no-removal. Pass `--auto-apply` to apply everything (including removals) without prompting — required for non-interactive runs.

If no subcommand is provided, default to `list`. For `secrets` with no further argument, default to `secrets list`.

### Pre-flight

Always verify `GCORE_API_KEY` is set first. If not, tell the user how to get and set it (`https://portal.gcore.com` → API Keys). Do not proceed.

---

## Subcommand: `list`

Fetch all apps and display as a formatted table.

**Direct API** (no MCP list-all tool yet):
```bash
APPS=$(curl -s "https://api.gcore.com/fastedge/v1/apps" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

Format as table: **ID**, **Name**, **Status**, **URL**

Status values: `0` = Disabled, `1` = Enabled, `2` = Suspended

```
ID      Name              Status    URL
─────   ────────────────  ────────  ──────────────────────────────
12345   my-app            Enabled   https://my-app.gcore.dev
12346   api-gateway       Enabled   https://api-gateway.gcore.dev
```

If no apps, suggest `/gcore-fastedge:scaffold` to create one.

---

## Subcommand: `get <id>`

**Via MCP (primary):** Use the `update-or-create-app` tool with `appId` parameter to fetch app details.

Display all app details: name, ID, status, binary ID, plan, env vars, URL.

**App stats** (direct API — no MCP tool yet):
```bash
STATS=$(curl -s "https://api.gcore.com/fastedge/v1/apps/$APP_ID/stats" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```
Show request count, error rates, and latency percentiles if stats are available.

**Local opt-out (only if user declined MCP):**
```bash
APP=$(curl -s "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

---

## Subcommand: `update <id>`

Ask the user what they want to update. Supported fields:

- **name** — Change app name
- **status** — Enable (1) or disable (0) the app
- **binary** — Update to a new binary ID (or re-deploy with `/gcore-fastedge:deploy`)
- **env_vars** — Add, update, or remove environment variables
- **secrets** — Add or update secrets by referencing secret IDs: `"secrets": {"SECRET_NAME": {"id": <secret-id>}}`
- **rsp_headers** — Add or update response headers
- **plan** — Change plan (basic/pro)

**For env_vars, secrets, rsp_headers — via MCP (primary):** Use the `update-env-vars-app` tool.

| Parameter | Value |
|-----------|-------|
| `appId` | App ID |
| `envVars` | JSON string of env vars (if updating) |
| `secrets` | JSON string of secrets (if updating) |
| `rspHeaders` | JSON string of response headers (if updating) |

The tool merges new values with existing config.

**For name, status, binary, plan — via MCP:** Use the `update-or-create-app` tool with `appId` and `binaryId`.

**Local opt-out (only if user declined MCP):**
```bash
curl -s -X PUT "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '<update-payload>'
```

Show the updated app details after the update.

---

## Subcommand: `delete <id>`

**Always confirm with the user before deleting.**

First, fetch app details (via MCP `update-or-create-app` with `appId`, or the local opt-out path if the user is not running MCP). Display the app name, ID, and URL.

Ask: "Are you sure you want to delete this app? This cannot be undone."

Only after user confirms — **direct API** (no MCP delete tool yet):
```bash
curl -s -X DELETE "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY"
```

Confirm deletion was successful.

---

## Subcommand: `secrets list`

**Direct API** (no MCP list-secrets tool yet):
```bash
SECRETS=$(curl -s "https://api.gcore.com/fastedge/v1/secrets" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

Format as table: **ID**, **Name**

```
ID      Name
─────   ────────────────
1001    API_TOKEN
1002    DB_PASSWORD
```

---

## Subcommand: `secrets get <name>`

**Via MCP (primary):** Use the `get-secret-id` tool.

| Parameter | Value |
|-----------|-------|
| `secretName` | Secret name to look up |

Returns the secret ID. Display it so the user can reference it in `update` commands.

**Local opt-out (only if user declined MCP):**
```bash
SECRET=$(curl -s "https://api.gcore.com/fastedge/v1/secrets?secret_name=$SECRET_NAME" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

---

## Subcommand: `sync-env <id-or-name>`

Read dotenv files from the project directory and push all environment variables, secrets, and response headers to a deployed app in one operation.

### Step 1: Identify the app

Resolve the argument to an app — accept either an app ID or app name.

### Step 2: Find and read dotenv files

Resolve `<source-dir>`:

- If `--from <dir>` was passed, `<source-dir>` is that directory (resolve relative to the project root if not absolute).
- Otherwise `<source-dir>` is the project root.

Search **only `<source-dir>`** (not recursively, not the project root when `--from` was given) for these files:

| File | Purpose |
|------|---------|
| `.env` | General dotenv file (parsed by prefix) |
| `.env.variables` | Environment variables only |
| `.env.secrets` | Secret references only |
| `.env.rsp_headers` | Response headers only |

All files are optional. If none are found in `<source-dir>`, tell the user (mention which directory was searched) and exit.

`--from` semantics are **simple replacement**: whatever's in `<source-dir>` is the complete env truth for this run. There is no layering with project-root `.env*` files when `--from` is set. Callers that want per-variant overrides should put a complete env set in each variant directory (e.g. `fixtures/germany/.env`).

### Step 3: Parse variables by prefix

| Prefix | Category | Example |
|--------|----------|---------|
| `FASTEDGE_VAR_ENV_` | Environment variable | `FASTEDGE_VAR_ENV_API_URL=https://api.example.com` → `{"API_URL": "https://api.example.com"}` |
| `FASTEDGE_VAR_SECRET_` | Secret reference | `FASTEDGE_VAR_SECRET_AUTH_TOKEN=my-auth-token` → look up secret named `my-auth-token` |
| `FASTEDGE_VAR_RSP_HEADER_` | Response header | `FASTEDGE_VAR_RSP_HEADER_X_Frame_Options=DENY` → `{"X-Frame-Options": "DENY"}` |

Variables in `.env.variables`, `.env.secrets`, `.env.rsp_headers` don't need prefixes — their category is implied by the filename.

### Step 4: Resolve secrets

**Via MCP (primary):** For each secret reference, use the `get-secret-id` tool to look up the ID.

Build the secrets payload: `{"SECRET_KEY": {"id": <resolved-id>}}`

If a secret name can't be resolved, warn the user and skip it.

**Local opt-out (only if user declined MCP):**
```bash
SECRET=$(curl -s "https://api.gcore.com/fastedge/v1/secrets?secret_name=$SECRET_NAME" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

### Step 5: Fetch current app state and compute the diff

Fetch the deployed app's current `env`, `secrets`, and `rsp_headers`.

**Via MCP (primary):** Use the `update-or-create-app` tool with `appId` to retrieve the current configuration.

**Local opt-out (only if user declined MCP):**
```bash
APP=$(curl -s "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

For each of the three categories (env, secrets, rsp_headers), compare the local parsed set against what's on the app and bucket every key into one of three sets:

| Set | Definition |
|---|---|
| **adds** | Key in `.env*` but not on the app |
| **changes** | Key in both, value differs |
| **removes** | Key on the app but not in `.env*` |

For secrets, compare on the **resolved secret ID** (the value after Step 4's `get-secret-id` lookup), not the local name string — a rename in `.env.secrets` that resolves to the same ID is a no-op, not a change.

If all three sets are empty across all three categories, the app is already in sync. Print:

```
Env already in sync with <source-dir> — nothing to push.
```

…and exit. No prompt, no Step 6, no Step 7.

The buckets feed directly into Step 6's policy decision.

### Step 6: Apply tiered confirmation policy

Behavior depends on the Step 5 buckets and whether `--auto-apply` was passed.

**Case A — Only adds and/or changes (no removes):** auto-apply. No prompt. Print a one-line summary, then proceed to Step 7:

```
Synced from <source-dir> to "<app-name>" (ID: <app-id>) — 3 env vars added, 1 changed.
```

This case includes the first-run case (deployed app has no env yet — everything is an add).

**Case B — Removes present, `--auto-apply` NOT passed:** print the full diff and prompt:

```
Source: <source-dir>

Adds:
  env     API_URL = https://api.example.com
  secret  AUTH_TOKEN → secret ID 1001

Changes:
  env     DEBUG = false   (was: true)

Removes (would delete from deployed app):
  env     OLD_VAR
  header  X-Legacy

Choose:
  [a] Apply adds and changes only (default — leaves OLD_VAR and X-Legacy intact)
  [b] Apply everything, including removals
  [c] Cancel sync
```

Use `AskUserQuestion` (three options, single-select; `[a]` first as the recommended/default). On `[a]`: apply adds + changes only and proceed to Step 7. On `[b]`: apply all three sets and proceed. On `[c]`: exit without touching the app.

Display only the buckets that have entries — never print an empty `Adds:` / `Changes:` / `Removes:` block. Categories are labeled per-line (`env`, `secret`, `header`) so the user sees what kind of value each key is.

**Case C — Removes present, `--auto-apply` passed:** apply all three sets without prompting. Print:

```
Synced from <source-dir> to "<app-name>" — 3 added, 1 changed, 2 removed (--auto-apply).
```

`--auto-apply` is the explicit opt-in for non-interactive runs (CI, scripted workflows). Without it, destructive diffs block on user input. The default-no-removal encodes the rule: keys on a deployed app that aren't in `.env*` may have been set intentionally via the portal or another workflow, and silently deleting them is a footgun.

### Step 7: Push to app

Build the **applied set** — the subset of buckets the Step 6 policy decided to act on (Case A: adds + changes; Case B `[a]`: adds + changes; Case B `[b]`: adds + changes + removes; Case C: all three).

**Adds + changes only (no removals applied) — via MCP (primary):** Use the `update-env-vars-app` tool, which merges the supplied values on top of the app's existing config:

| Parameter | Value |
|-----------|-------|
| `appId` | App ID |
| `envVars` | JSON string of env adds + changes (only) |
| `secrets` | JSON string of secret adds + changes (only) |
| `rspHeaders` | JSON string of header adds + changes (only) |

**Removals applied — direct API PUT (replacement semantics):** Build the **final desired state** for each changed category (= `current_app_value` + adds + changes − removes) and PUT the complete app state. MCP's `update-env-vars-app` and a PATCH with `{ "env": {} }` both merge — neither can express removals, since an empty object means "no keys to merge in", not "wipe everything". Only direct-PUT works.

The PUT endpoint requires the full resource. At minimum include `name`, `binary`, and `status` (the API returns `400 property "binary" is missing` otherwise) — read them from the Step 5 GET and pass through unchanged. Include only the categories whose diff was non-empty (env / secrets / rsp_headers); omit unchanged categories so values you weren't asked to touch are left alone.

```bash
curl -s -X PUT "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<app-name>",
    "binary": <current-binary-id>,
    "status": <current-status>,
    "env": {<final-env-state>}
  }'
```

**Local opt-out (only if user declined MCP, adds + changes only case):** same direct-PUT path as above, but assemble the body as `current_app_value + adds + changes` without applying any removes.

Show the result and confirm success. On any API error (4xx/5xx), surface the response body and stop — do not silently swallow.
