---
name: manage
disable-model-invocation: true
argument-hint: "[list|get|update|delete|secrets|sync-env] [app-id] [--from <dir>] [--auto-apply]"
description: Manage FastEdge apps, env vars, secrets, and headers using MCP-first operations
---

# FastEdge Manage (Codex)

Manage deployed FastEdge apps and runtime configuration. MCP-first; direct API only on explicit opt-out.

## Supported Subcommands

- `list`
- `get <id>`
- `update <id>`
- `delete <id>`
- `secrets list`
- `secrets get <name>`
- `sync-env <id-or-name>`

Defaults:

- no subcommand → `list`
- `secrets` with no argument → `secrets list`

## Flags

- `--from <dir>` — for `sync-env`, read dotenv files from `<dir>` instead of project root. **Simple replacement**: `<dir>` is the complete env truth for that run — no layering with project-root `.env*`, no fallback if `<dir>` is empty.
- `--auto-apply` — for `sync-env`, skip confirmation and apply all changes including destructive removals. Required for non-interactive runs.

## Pre-Flight

Always verify API key first. Halt and emit setup guidance if `GCORE_API_KEY` (or legacy `FASTEDGE_API_KEY`) is unset.

## MCP Coverage Matrix

| Operation | Tool | Status |
|---|---|---|
| `list` (all apps) | `gcore_api` GET `/fastedge/v1/apps` | Partial — MCP supports name-search; direct API for full list |
| `get <id>` | `gcore_api` GET `/fastedge/v1/apps/<id>` | ✓ |
| `update <id>` | `gcore_api` PATCH/PUT `/fastedge/v1/apps/<id>` | ✓ |
| `delete <id>` | `gcore_api` DELETE `/fastedge/v1/apps/<id>` | Gap — direct API |
| `secrets list` | `gcore_api` GET `/fastedge/v1/secrets` | Gap — direct API |
| `secrets get <name>` | `gcore_api` GET `/fastedge/v1/secrets/<id>` | ✓ (name → id resolution via list) |
| `sync-env` (adds/changes) | `update-env-vars-app` | ✓ |
| `sync-env` (removals) | `gcore_api` PUT `/fastedge/v1/apps/<id>` | Forced direct PUT — `update-env-vars-app` merges, does not remove |
| stats | `gcore_api` GET `/fastedge/v1/apps/<id>/stats` | Gap — direct API |

There is **no** `update-or-create-app` MCP tool. The actual create/update path goes through `gcore_api` against the FastEdge REST API.

### Direct API fallback policy

Drop to direct API for the **whole skill** only when the user explicitly opts out of MCP (e.g. "I don't want to run Docker"). The matrix Gaps above are per-operation, not a fallback-first stance.

## Command Behavior

### `list`

- Fetch all apps (direct API for full list; MCP can search by name).
- Render table: ID, name, status, URL.
- If empty, suggest scaffold flow.

### `get <id>`

- Fetch app details via MCP `gcore_api`.
- Return status, binary, plan, env/secrets/rsp headers summary, URL.
- Include stats if available.

### `update <id>`

Support updates for: name, status, binary, env vars, secrets, response headers, plan.

Echo exact fields changed and show resulting app summary.

### `delete <id>`

- Show target app details.
- Require explicit confirmation.
- Delete only after confirmation.
- Confirm deletion response.

### `secrets list` / `secrets get <name>`

- list: return ID/name table.
- get: resolve and return secret ID. Never print secret values.

### `sync-env <id-or-name>`

Read dotenv files from project root (or `<dir>` if `--from <dir>`):

- `.env`
- `.env.variables`
- `.env.secrets`
- `.env.rsp_headers`

**Search scope**: non-recursive in the source directory. When `--from` is set, do not fall back to project root.

Parse prefixes:

- `FASTEDGE_VAR_ENV_*` → env vars
- `FASTEDGE_VAR_SECRET_*` → secrets (resolve name → ID)
- `FASTEDGE_VAR_RSP_HEADER_*` → response headers

Compute diff against deployed app state. Classify by Case.

#### Three-tier confirmation policy

| Case | Diff | Behavior |
|---|---|---|
| A | adds/changes only, no removals | Auto-apply silently — no prompt |
| B | has removals, no `--auto-apply` | Prompt with three options:<br>`[a]` apply adds+changes only, skip removals (default)<br>`[b]` apply all (including removals)<br>`[c]` cancel |
| C | has removals + `--auto-apply` | Apply all silently |

**Default-no-removal is a safety rule.** Destructive env var removals must not land on a production deployed app without explicit user opt-in.

#### Secrets lookup failure

When a `FASTEDGE_VAR_SECRET_*` reference can't be resolved to a secret ID, **warn the user and skip that entry** — do not silently drop, do not error out the whole sync.

A secret rename that resolves to the same ID is a **no-op**, not a change. Compare on resolved ID, not on the local name string.

#### `update-env-vars-app` payload shape

```
{
  "appId": <id>,
  "envVars": "<JSON-encoded string>",
  "secrets": { "NAME": { "id": <secret-id> } },
  "rspHeaders": { "X-Header": "value" }
}
```

Note: `envVars` (and the other category fields where applicable) are **JSON-encoded strings**, not nested objects.

#### Removals → direct PUT semantics

`update-env-vars-app` merges, not replaces. Removing an env var requires a direct PUT to `/fastedge/v1/apps/<id>` with a full app representation. Minimum required fields: `name`, `binary`, `status`. Include only categories whose diff was non-empty.

Never print secret values.

## Completion Output

Return concise result:

- target app
- operations performed
- changed keys (redacted where sensitive)
- warnings/skips (e.g. unresolved secrets)
- verification command

## Worked Examples

These anchor expected behavior and the three-tier confirmation safety rule. Mirror the structure when handling real requests.

### Example 1 — List + inspect

**User prompt**: "list my fastedge apps and show me details for the one called product-cache"

**Behavior**:

- Run `list` first: `gcore_api` GET `/fastedge/v1/apps` (direct API for full list — MCP supports name-search but not full enumeration).
- Render table.
- For the named app, resolve id from the list, then run `get <id>`: `gcore_api` GET `/fastedge/v1/apps/<id>`.

**Completion output**:

```
Apps (3):

  ID        NAME             STATUS   URL
  4732724   product-cache    active   https://product-cache-4732724.fastedge.cdn.gc.onl/
  4732801   geo-router       active   https://geo-router-4732801.fastedge.cdn.gc.onl/
  4732932   webhook-relay    paused   https://webhook-relay-4732932.fastedge.cdn.gc.onl/

product-cache (4732724):
  status:    active     binary:  88514     plan:     basic
  env vars:  3          secrets: 1         rsp hdrs: 0
  URL:       https://product-cache-4732724.fastedge.cdn.gc.onl/
```

### Example 2 — sync-env with destructive removal (Case B)

**User prompt**: "sync-env product-cache"

**Behavior**:

- Resolve `product-cache` → app id 4732724.
- Source dir: project root (no `--from`).
- Non-recursive scan of `.env`, `.env.variables`, `.env.secrets`, `.env.rsp_headers`. Parse `FASTEDGE_VAR_ENV_*`, `FASTEDGE_VAR_SECRET_*`, `FASTEDGE_VAR_RSP_HEADER_*`.
- Compute diff against deployed env via `gcore_api` GET. Diff: 2 adds, 1 change, 1 removal.
- **Case B**: removals present, no `--auto-apply` → prompt with three options. Default `[a]` (skip removals).
- Never print secret values.

**Completion output (before prompt)**:

```
sync-env diff — product-cache (4732724)

  ADD       FASTEDGE_VAR_ENV_FEATURE_FLAG_X       (env)
  ADD       FASTEDGE_VAR_SECRET_STRIPE_KEY        (secret → id 88421)
  CHANGE    FASTEDGE_VAR_ENV_REGION               (env)
  REMOVE    FASTEDGE_VAR_ENV_OLD_FLAG             (env)

This run includes a removal. Default is to skip removals.
  [a] apply adds + changes only (default)
  [b] apply all (including removals)
  [c] cancel
```

If user picks `[a]`: apply adds + changes via `update-env-vars-app` MCP tool. Skip the removal. Verification command at end.

If user picks `[b]`: removal forces a direct PUT — `update-env-vars-app` merges, doesn't remove. PUT body must be full app representation with minimum fields `name`, `binary`, `status` + only the categories with non-empty diff.

### Example 3 — Degraded mode: missing API key

**User prompt**: "list"

**Behavior**: Pre-flight check fails — neither `GCORE_API_KEY` nor `FASTEDGE_API_KEY` is set. Halt before any operation.

**Completion output**:

```
✗ Cannot run manage operations — no API key set.

Set the environment variable, then re-run:

  export GCORE_API_KEY="<your-key>"

Get a key from https://portal.gcore.com → API Keys.

Note: legacy FASTEDGE_API_KEY is also accepted.
```
