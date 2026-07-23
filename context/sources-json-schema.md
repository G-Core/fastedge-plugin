# sources.json v2 Schema Reference

> Supports Constitution Principle IX: `sources.json` is Law.
> This document is the authoritative specification for the `sources.json` manifest.

---

## Purpose

`sources.json` lives at the root of the `fastedge-plugin` repo. It is the **slim pipeline config** that controls:

- Which source repos are fetched during automated runs
- Where to find each repo's contract directory (`fastedge-plugin-source/`)
- Where to find synthesis intent files in the plugin repo
- Which AI agents generate and review updates

Content mapping (which files map to which reference docs) is NOT in `sources.json` — it lives in each source repo's `manifest.json`. See **Two-Level Config** below.

---

## File Location

```
fastedge-plugin/
└── sources.json          ← pipeline config (how to fetch + which agents)
```

---

## Two-Level Config

The v2 pipeline splits config between two files:

| File | Lives In | Controls | Maintained By |
|------|----------|----------|---------------|
| `sources.json` | Plugin repo | HOW to fetch (URL, ref, trigger, agents) | Plugin maintainer |
| `manifest.json` | Source repo (`fastedge-plugin-source/`) | WHAT to provide (source doc paths, target_mapping, validation) | Source repo maintainer |

The pipeline:
1. Reads `sources.json` for repo URL, ref, contract_path, agents
2. Sparse-checkouts `contract_path` from the source repo (gets manifest.json)
3. Reads `manifest.json` from the checkout for `sources` and `target_mapping`
4. Sparse-checkouts the doc file paths listed in `sources.*.files`
5. Uses `target_mapping` to derive what to generate and where
6. Uses `intent_dir` from `sources.json` for synthesis intent files

---

## Top-Level Structure

```json
{
  "version": "2.0",
  "repos": [ ...RepoEntry ]
}
```

| Field     | Type   | Required | Description                                          |
| --------- | ------ | -------- | ---------------------------------------------------- |
| `version` | string | yes      | Must be `"2.0"`. Validated by Rule 0. |
| `repos`   | array  | yes      | List of source repos to monitor and fetch from.      |

---

## RepoEntry

```json
{
  "id": "fastedge-test",
  "github_url": "https://github.com/G-Core/fastedge-test",
  "ref": "latest-release",
  "trigger": "release",
  "contract_path": "fastedge-plugin-source/",
  "intent_dir": "agent-intent-skills/fastedge-test/",
  "generator_agent": "claude",
  "reviewer_agent": "openai"
}
```

| Field             | Type   | Required | Description |
| ----------------- | ------ | -------- | ----------- |
| `id`              | string | yes      | Unique identifier. Used in baseline tags and traceability frontmatter. Kebab-case. |
| `github_url`      | string | yes      | Full HTTPS URL of the GitHub repo. No trailing slash. |
| `ref`             | string | yes      | What to check out. See **Ref Strategy** below. |
| `trigger`         | string | yes      | What causes this repo to be fetched. See **Trigger Types** below. |
| `contract_path`   | string | yes      | Path to the contract directory in the source repo. Must end with `/`. Contains `manifest.json` only (no content files). |
| `intent_dir`      | string | yes      | Path to synthesis intent files in the plugin repo, relative to `sources.json`. Must end with `/`. Directory must exist. |
| `generator_agent` | string | yes      | AI agent that generates content. See **Agent Values** below. |
| `reviewer_agent`  | string | yes      | AI agent that reviews content. **Must differ from `generator_agent`**. |

### Removed in v2

These fields from v1 are **no longer valid** and will cause a validation error:

| Field          | Replacement |
|----------------|-------------|
| `sparse_paths` | `contract_path` — the pipeline fetches the contract directory, then doc paths from manifest |
| `updates[]`    | `manifest.json` `target_mapping` — content mapping lives in the source repo |

### Ref Strategy

| Value              | Behavior                                                                               |
| ------------------ | -------------------------------------------------------------------------------------- |
| `"latest-release"` | Resolves to the most recent GitHub release tag at run time. Preferred for stable SDKs. |
| `"main"`           | Always fetches the HEAD of the default branch. Use for repos with no release cadence.  |
| `"vX.Y.Z"`         | Pins to a specific release tag. Only use this when a manual pin is intentional.        |

### Trigger Types

| Value        | Behavior                                                                                |
| ------------ | --------------------------------------------------------------------------------------- |
| `"release"`  | Runs when the source repo sends `repository_dispatch` (fastedge-ref-update). |
| `"schedule"` | Runs on the configured cron schedule regardless of releases.                 |
| `"both"`     | Runs on either trigger.                                                      |

### Agent Values

| Value       | Status              | Agent                                                        |
| ----------- | ------------------- | ------------------------------------------------------------ |
| `"claude"`  | **Supported**       | Anthropic Claude via Claude Code CLI — the only supported generator today |
| `"openai"`  | **Supported**       | OpenAI gpt-4o via REST API — the only supported reviewer today |
| `"codex"`   | Reserved (not impl) | OpenAI Codex / ChatGPT                                       |
| `"gemini"`  | Reserved (not impl) | Google Gemini                                                |

> **Current implementation**: `invoke-agent.sh` does not branch on these field values.
> The generator role always invokes Claude (`claude -p …`); the reviewer role always calls
> OpenAI gpt-4o. The fields document intent and enforce the generator ≠ reviewer constraint
> at validation time.

---

## Intent File Resolution

The pipeline resolves intent files by matching the **path suffix after `reference/`** in the reference file to a file in `intent_dir`. This preserves subfolder structure:

| Reference file path | Path suffix | Intent file lookup |
|---|---|---|
| `skills/scaffold/reference/http/kv-store-ts.md` | `http/kv-store-ts.md` | `<intent_dir>/http/kv-store-ts.md` |
| `skills/fastedge-docs/reference/cdn/examples-body-rust.md` | `cdn/examples-body-rust.md` | `<intent_dir>/cdn/examples-body-rust.md` |
| `skills/fastedge-docs/reference/sdk-reference-js.md` | `sdk-reference-js.md` | `<intent_dir>/sdk-reference-js.md` |

When found, the intent file content is injected into the generator prompt as a `## Synthesis Instructions` block.

### Intent Directory Structure

Intent directories mirror the reference file subfolder structure:

```
agent-intent-skills/<repo-id>/
  # Root-level — matches reference files at root (no subfolder)
  sdk-reference-js.md
  quickstart.md
  _scaffold-blueprint-base.md    # Shared base: all scaffold intents reference this
  _docs-pattern-base.md          # Shared base: all docs intents reference this

  # Subfolders mirror reference/http/ and reference/cdn/
  http/
    base-ts.md                   # scaffold blueprint intent
    kv-store-ts.md               # scaffold blueprint intent
    examples-kv-store-js.md      # docs pattern intent
  cdn/
    base-rust.md                 # scaffold blueprint intent
    body-rust.md                 # scaffold blueprint intent
    examples-body-rust.md        # docs pattern intent
```

**Key rules:**
- Shared base files (`_scaffold-blueprint-base.md`, `_docs-pattern-base.md`) live at the intent dir root — referenced from subfolders via `../`
- Subfoldered intent files use `{concept}-{lang}.md` naming — the subfolder provides app_type context
- Scaffold intents and docs intents coexist in the same subfolder, distinguished by the `examples-` prefix on docs pattern files
- Files with the same basename can exist in different subfolders (e.g. `http/base-rust.md` and `cdn/base-rust.md`) — the path-based matching resolves them correctly

---

## manifest.json — Source-Side Contract

Each source repo's `fastedge-plugin-source/manifest.json` declares which existing doc files the repo provides and where they map to in the plugin:

```json
{
  "$schema": "https://fastedge-plugin-source/manifest/v1",
  "repo_id": "fastedge-test",
  "version": "1.0.0",
  "sources": {
    "test-framework": {
      "files": ["docs/TEST_FRAMEWORK.md"],
      "required": true,
      "description": "Test framework API — defineTestSuite, runAndExit, runFlow, assertions"
    },
    "test-config": {
      "files": ["docs/TEST_CONFIG.md", "schemas/fastedge-config.test.schema.json"],
      "required": true,
      "description": "Test configuration schema and usage examples"
    }
  },
  "target_mapping": {
    "test-framework": {
      "reference_file": "plugins/gcore-fastedge/skills/test/reference/test-framework.md",
      "section": null
    },
    "test-config": {
      "reference_file": "plugins/gcore-fastedge/skills/test/reference/test-config.md",
      "section": null
    }
  },
  "validation": {
    "mode": "advisory",
    "strict_fields": ["test-framework"]
  }
}
```

### Key differences from old `provides`-based schema

| Old (`provides`) | New (`sources`) | Why |
|-----------------|----------------|-----|
| `file`: single path in contract dir | `files`: array of paths relative to repo root | Points at actual docs, not generated copies |
| `generated: true/false` | Removed | No generated files in contract dir — `docs/` is maintained directly |
| Files lived in `fastedge-plugin-source/` | Files live in `docs/` (or wherever natural) | Single source of truth |

The full manifest schema is defined in `SOURCE_CONTRACT.md`.

---

## Contract Validation

`validate-contract.sh` validates a contract directory against these rules:

1. `manifest.json` exists and parses as valid JSON
2. `$schema` field present and matches `https://fastedge-plugin-source/manifest/*`
3. Required source entries (`required: true`) have non-empty `files` arrays. When `repo_root` is provided, also verifies each file exists and is non-empty. Entries listed in `strict_fields` are always enforced as errors; others follow the `validation.mode` (advisory = warning, strict = error).
5. `target_mapping` `reference_file` paths start with `plugins/`
6. `target_mapping` keys have corresponding `sources` entries (warning only)

There is no Rule 4 — it was removed when the `sources`-based schema replaced `provides` (the old Rule 4 checked generated-file headers, which no longer exist).

**Note**: Rule 3 file-existence checks require the optional `repo_root` argument. Without it, only manifest structure is validated. The pipeline does a two-step sparse checkout: first the contract directory (for the manifest), then the doc paths listed in the manifest — `repo_root` is passed after the second checkout.

Validation runs in two places:
- **Source repo CI** — catches issues before merge
- **Plugin pipeline** — `process-repos.sh` calls `validate_contract()` after fetch

### Validation Modes

| Mode | Behavior |
|------|----------|
| `advisory` (default) | Warnings only — build continues |
| `strict` | Failures break the build |
| `strict_fields` | Array of source keys that are always required regardless of mode |

---

## sources.json Validation Rules

`validate-sources.sh` checks these rules before any fetch runs:

0. Version must be `"2.0"`
1. All `id` values are unique across `repos`
2. All `github_url` values are reachable via `gh api`
3. No `generator_agent` equals `reviewer_agent` within the same repo
4. All `contract_path` values end with `/`
5. All `intent_dir` values end with `/` and the directory exists
6. No v1 fields (`updates[]`, `sparse_paths`) are present

A validation failure aborts the workflow before any sparse checkout begins.

---

## Traceability Frontmatter

Every automated reference file update prepends or updates a frontmatter block:

```markdown
<!--
  auto-updated: true
  sources:
    - id: fastedge-test
      ref: v2.1.0
      commit: abc1234
      updated: 2026-03-10
-->
```

The reviewing agent validates this block is present and accurate before approving.

---

## Current State

See `sources.json` at the repo root for the current configured repos. As of April 2026:

- **`fastedge-test`** — fully integrated (6 reference docs in `skills/test/reference/`)
- **`fastedge-sdk-js`** — fully integrated (1 SDK ref + 5 HTTP scaffold blueprints + 5 HTTP example patterns + 4 cross-cutting docs)
- **`fastedge-sdk-rust`** — fully integrated (2 SDK refs + 2 HTTP + 4 CDN scaffold blueprints + 1 HTTP + 3 CDN example patterns + 1 CDN apps doc)

Each source repo has a `fastedge-plugin-source/CONVENTIONS.md` documenting the naming rules and intent file matching contract.

---

## How to Add a New Source Repo

1. **Create the contract directory** in the source repo: `fastedge-plugin-source/manifest.json` (see manifest.json schema above).

2. **Add a `RepoEntry`** to `sources.json`:

```json
{
  "id": "my-new-repo",
  "github_url": "https://github.com/G-Core/my-new-repo",
  "ref": "latest-release",
  "trigger": "release",
  "contract_path": "fastedge-plugin-source/",
  "intent_dir": "agent-intent-skills/my-new-repo/",
  "generator_agent": "claude",
  "reviewer_agent": "openai"
}
```

3. **Create the intent directory** at `agent-intent-skills/my-new-repo/` with:
   - `_scaffold-blueprint-base.md` and `_docs-pattern-base.md` at the root — copy from an existing repo's intent dir (e.g., `fastedge-sdk-js/`) and adjust language-specific details
   - `http/` and/or `cdn/` subfolders mirroring the reference file structure
   - Per-example intent files inside the subfolders — named `{concept}-{lang}.md` for scaffold, `examples-{concept}-{lang}.md` for docs patterns
   - Each intent file references the shared base via `../_scaffold-blueprint-base.md` or `../_docs-pattern-base.md`
   - Base skeleton intent files (e.g. `http/base-ts.md`) are standalone (different structure from feature intents)

4. **Create the target reference files** (empty or with placeholder) at the paths declared in the source repo's `manifest.json` `target_mapping`.

5. **Commit** `sources.json`, the intent files, and the placeholder reference files to `main`.

6. The next pipeline run will process the new repo.

**Rules enforced automatically**:
- `contract_path` must end with `/` (Rule 4)
- `intent_dir` must end with `/` and directory must exist (Rule 5)
- `generator_agent` must differ from `reviewer_agent` (Rule 3)
- No v1 fields (`updates[]`, `sparse_paths`) allowed (Rule 6)

**To add webhook support** in the source repo's release workflow:

```yaml
- name: Trigger fastedge-plugin reference update
  run: |
    curl -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${{ secrets.FASTEDGE_PLUGIN_DISPATCH_TOKEN }}" \
      https://api.github.com/repos/G-Core/fastedge-plugin/dispatches \
      -d '{
        "event_type": "fastedge-ref-update",
        "client_payload": {
          "source_repo_id": "my-new-repo",
          "ref": "${{ github.ref_name }}",
          "commit": "${{ github.sha }}"
        }
      }'
```

The `FASTEDGE_PLUGIN_DISPATCH_TOKEN` must be a PAT with `repo` scope stored in the source repo's secrets.
