---
disable-model-invocation: false
argument-hint: "[list|get|update|delete|secrets|sync-env] [app-id] [--from <dir>] [--auto-apply]"
description: List, get, update, or delete FastEdge apps, manage secrets, and sync dotenv files
---

# Manage FastEdge Apps

Manage your deployed FastEdge applications.

## MCP Server Integration

This skill runs API operations through the **FastEdge MCP server** (the executor layer). The plugin's bundled `.mcp.json` launches `ghcr.io/g-core/fastedge-mcp-server:latest` automatically; this is the default path.

Every operation goes through the MCP server's `gcore_api` tool (method + path + optional query/body). The MCP server holds the credential: an API key from the MCP config, or a portal sign-in session. The skill never needs `GCORE_API_KEY` itself, and on the MCP path it never runs `curl`.

If MCP tool calls fail, diagnose first (Docker running? Network?). If a call returns `auth_required`, follow the instructions in that result (it offers a portal sign-in); never ask the user to paste a token or code into the chat, and don't fall back to `curl`. Only drop to direct API for the whole skill if the user explicitly chooses to skip MCP — warn them they're outside the supported default, and that the direct path needs `GCORE_API_KEY`. See `/gcore-fastedge:deploy` for the canonical MCP config.

### MCP Operations

| Operation | `gcore_api` call |
|-----------|------------------|
| List apps | GET `/fastedge/v1/apps` |
| Get app | GET `/fastedge/v1/apps/{id}` |
| Update app (merge fields) | PATCH `/fastedge/v1/apps/{id}` |
| Replace app config (removals) | PUT `/fastedge/v1/apps/{id}` |
| Delete app | DELETE `/fastedge/v1/apps/{id}` |
| List secrets | GET `/fastedge/v1/secrets` |
| Get secret ID by name | GET `/fastedge/v1/secrets?secret_name=<name>` |
| App stats | GET `/fastedge/v1/stats/calls` and `/fastedge/v1/stats/app_duration` with `id`, `from`, `to`, `step` |

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

Don't check `GCORE_API_KEY` in your shell: the MCP server may hold a key from its config or a portal sign-in session. Just make the first MCP call. If it returns `auth_required`, follow its instructions, then retry. If the MCP server itself is unavailable, diagnose as above.

---

## Subcommand: `list`

Fetch all apps and display as a formatted table.

**Via MCP (primary):** `gcore_api` GET `/fastedge/v1/apps`.

**Local opt-out (only if user declined MCP):**
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

**Via MCP (primary):** `gcore_api` GET `/fastedge/v1/apps/{id}`.

Display all app details: name, ID, status, binary ID, plan, env vars, URL.

**App stats** — `gcore_api` GET `/fastedge/v1/stats/calls` and GET `/fastedge/v1/stats/app_duration`, each with query `id=<app-id>`, `from` and `to` (RFC3339; e.g. the last 24 hours) and `step` (seconds, e.g. `3600`). Show request counts by status, and duration percentiles, if stats are available.

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

**Via MCP (primary):** `gcore_api` PATCH `/fastedge/v1/apps/{id}` with only the fields being changed, e.g. `{ "status": 0 }` or `{ "env": { "API_URL": "https://api.example.com" } }`. PATCH merges `env`, `secrets` and `rsp_headers` with the existing values, so it can add or change keys but not remove them; to remove keys, use the PUT path in `sync-env` Step 7.

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

First, fetch app details (via MCP `gcore_api` GET `/fastedge/v1/apps/{id}`, or the local opt-out path if the user is not running MCP). Display the app name, ID, and URL.

Ask: "Are you sure you want to delete this app? This cannot be undone."

Only after user confirms — **via MCP (primary):** `gcore_api` DELETE `/fastedge/v1/apps/{id}`.

**Local opt-out (only if user declined MCP):**
```bash
curl -s -X DELETE "https://api.gcore.com/fastedge/v1/apps/$APP_ID" \
  -H "Authorization: APIKey $GCORE_API_KEY"
```

Confirm deletion was successful.

---

## Subcommand: `secrets list`

**Via MCP (primary):** `gcore_api` GET `/fastedge/v1/secrets`.

**Local opt-out (only if user declined MCP):**
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

**Via MCP (primary):** `gcore_api` GET `/fastedge/v1/secrets` with query `secret_name=<name>`.

Returns the matching secret, including its ID. Display it so the user can reference it in `update` commands.

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

**Via MCP (primary):** For each secret reference, look up the ID with `gcore_api` GET `/fastedge/v1/secrets` and query `secret_name=<name>`.

Build the secrets payload: `{"SECRET_KEY": {"id": <resolved-id>}}`

If a secret name can't be resolved, warn the user and skip it.

**Local opt-out (only if user declined MCP):**
```bash
SECRET=$(curl -s "https://api.gcore.com/fastedge/v1/secrets?secret_name=$SECRET_NAME" \
  -H "Authorization: APIKey $GCORE_API_KEY")
```

### Step 5: Fetch current app state and compute the diff

Fetch the deployed app's current `env`, `secrets`, and `rsp_headers`.

**Via MCP (primary):** `gcore_api` GET `/fastedge/v1/apps/{id}`.

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

For secrets, compare on the **resolved secret ID** (the value after Step 4's lookup), not the local name string — a rename in `.env.secrets` that resolves to the same ID is a no-op, not a change.

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

**Adds + changes only (no removals applied) — via MCP (primary):** `gcore_api` PATCH `/fastedge/v1/apps/{id}`, which merges the supplied values on top of the app's existing config. Body: only the categories with adds/changes, e.g. `{ "env": {<adds + changes>}, "secrets": {<adds + changes>}, "rsp_headers": {<adds + changes>} }`.

**Removals applied — PUT (replacement semantics), via MCP (primary):** `gcore_api` PUT `/fastedge/v1/apps/{id}`. Build the **final desired state** for each changed category (= `current_app_value` + adds + changes − removes) and PUT the complete app state. A PATCH with `{ "env": {} }` merges — it can't express removals, since an empty object means "no keys to merge in", not "wipe everything". Only PUT works.

The PUT endpoint requires the full resource. At minimum include `name`, `binary`, and `status` (the API returns `400 property "binary" is missing` otherwise) — read them from the Step 5 GET and pass through unchanged. Include only the categories whose diff was non-empty (env / secrets / rsp_headers); omit unchanged categories so values you weren't asked to touch are left alone.

The same body as a direct call (local opt-out only):

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
