# fastedge-plugin — Developer Instructions

## Governance (REQUIRED)

Read `AGENTS.md` for company-wide agent rules. These are mandatory and override any conflicting behavior. Key rules: never go beyond the assigned task, never change code that was not asked to change, never "improve" or "optimize" without a clear request, always distinguish observations from action requests.

---

## What This Repo Is

A **Claude Code plugin** for Gcore FastEdge. It gives Claude Code users skills to scaffold, deploy, and manage FastEdge apps via natural language.

This is NOT a traditional app — there is no build step, no compiled output, no server. Everything is Markdown files that Claude Code reads as context and skills.

---

## Two Separate Concerns

| Location                  | Audience              | Purpose                                                                    |
| ------------------------- | --------------------- | -------------------------------------------------------------------------- |
| `plugins/gcore-fastedge/` | Plugin **users**      | Loaded when plugin is installed — CLAUDE.md knowledge base + skill prompts |
| `context/` (this level)   | Plugin **developers** | Architecture decisions, maintenance guides, design rationale               |

A root-level `CLAUDE.md` (this file) is only read when someone works on the plugin itself, not by plugin users.

---

## Quick Reference

**Install for testing (session only):**

```bash
claude --plugin-dir /path/to/fastedge-plugin
```

**Install persistently:**

```bash
/plugin marketplace add /path/to/fastedge-plugin
/plugin install gcore-fastedge@gcore-fastedge-marketplace
```

**Plugin skills:**

- `/gcore-fastedge:scaffold` — blueprint-driven project scaffolding from SDK examples
- `/gcore-fastedge:deploy` — build + upload binary + create/update app
- `/gcore-fastedge:manage` — list, get, update, delete, secrets, sync-env
- `/gcore-fastedge:fastedge-docs` — auto-invoked docs skill
- `/gcore-fastedge:test` — write & run tests using `@gcoredev/fastedge-test`
  (generate complete test suites or scaffold stub files; creates test-config.json for debugger)

---

## Repository Structure

```
fastedge-plugin/
├── CLAUDE.md                          # This file (developer instructions)
├── README.md                          # User-facing installation guide
├── sources.json                       # Pipeline config (v2 — slim, manifest-driven)
├── docs/                              # Human documentation (doctor-required)
│   ├── INDEX.md                       # Docs entry point
│   └── quickstart.md                  # Install + first skill walkthrough
├── context/                           # Developer context (read for maintenance tasks)
│   ├── CONTEXT_INDEX.md               # Start here
│   ├── REFERENCE_MATERIAL.md          # Reference file sources + pipeline architecture
│   ├── sources-json-schema.md         # Authoritative v2 schema + manifest schema
│   └── TEMPLATE_STRATEGY.md           # Template hardcoding rationale + audit process
│
├── .github/workflows/
│   ├── sync-reference-docs.yml        # Reference doc sync pipeline
│   ├── doctor.yml                     # Agent-toolkit doctor (collect → act → analyze)
│   ├── collect.py                     # Doctor collect job logic
│   ├── doctor-analyze.md              # Doctor analyze prompt
│   └── doctor-analyze.lock.yml        # Compiled reusable workflow (gh-aw)
│
├── scripts/sync/                      # Pipeline scripts
│   ├── validate-sources.sh            # Validates sources.json v2 (7 rules)
│   ├── validate-contract.sh           # Validates contract directory (6 rules)
│   ├── fetch-repo.sh                  # Sparse checkout contract_path; baseline tags
│   ├── invoke-agent.sh                # Generator / reviewer / splice roles
│   ├── manage-pr.sh                   # Create/update PRs via gh CLI
│   ├── process-repos.sh              # Main pipeline loop
│   ├── templates/
│   │   ├── generation-config-template.md  # .generation-config.md template for source repos
│   │   └── generate-docs-template.sh     # generate-docs.sh template for source repos
│   └── tests/                         # 7 suites, 63 tests
│
├── agent-intent-skills/               # Synthesis instructions per repo
│   └── fastedge-test/                 # Intent files for fastedge-test reference docs
│
├── .claude-plugin/
│   ├── marketplace.json               # Marketplace container descriptor
│   └── plugin.json                    # Root plugin manifest
│
└── plugins/gcore-fastedge/            # The actual plugin (what users get)
    ├── .claude-plugin/
    │   └── plugin.json                # Plugin descriptor (name, version, keywords)
    ├── CLAUDE.md                      # Shared knowledge base (API, SDK, auth, builds)
    └── skills/
        ├── scaffold/
        │   ├── SKILL.md               # Blueprint-driven scaffold flow
        │   └── reference/
        │       ├── http/              # HTTP app blueprints (base + features)
        │       └── cdn/               # CDN app blueprints (base + features)
        ├── deploy/SKILL.md            # Build → upload binary → create/update app
        ├── manage/SKILL.md            # App and secret management subcommands
        └── fastedge-docs/
            ├── SKILL.md               # Docs entry point
            └── reference/
                ├── sdk-reference-js.md
                ├── sdk-reference-rust.md
                ├── host-services-rust.md
                ├── platform-overview.md
                ├── best-practices.md
                ├── error-codes.md
                ├── http/              # HTTP app examples — appType is the folder
                │   └── examples-{concept}-{lang}.md
                └── cdn/               # CDN app examples — appType is the folder
                    └── examples-{concept}-{lang}.md
```

---

## Discovery Guide

**Read when working on:**

| Task                                 | Read                                                                 |
| ------------------------------------ | -------------------------------------------------------------------- |
| Understanding the plugin structure   | This file                                                            |
| Scaffold skill / template management | `context/TEMPLATE_STRATEGY.md`                                       |
| Deploy or manage skill logic         | `plugins/gcore-fastedge/skills/deploy/SKILL.md` or `manage/SKILL.md` |
| Shared API / SDK knowledge           | `plugins/gcore-fastedge/CLAUDE.md`                                   |
| Updating docs reference content      | `plugins/gcore-fastedge/skills/fastedge-docs/reference/`             |

---

## Key Relationships

- **`FastEdge-sdk-js` / `FastEdge-sdk-rust`** — source repos for scaffold blueprints. The auto-ref-update pipeline generates blueprint files from SDK examples and keeps them current via PR. `create-fastedge-app` remains a human-facing npm CLI tool only — the plugin does not use it.
- **`fastedge-test`** — local WASM test runner. The `/gcore-fastedge:test` skill wraps this. Future work: integrate into deploy skill as a pre-deploy test step (see `context/TDD_ROADMAP.md`).
- **`FastEdge-mcp-server`** — planned integration target. Plugin will delegate build/deploy execution to MCP server (containerized toolchains, API gateway) while retaining workflow orchestration and intelligence. See `context/MCP_INTEGRATION.md` for phases and impact on current work. **When modifying deploy/manage skills or onboarding source repos, read MCP_INTEGRATION.md first.**

---

## TDD Integration

Testing skill is live. Scaffold and deploy integration is planned. See `context/TDD_ROADMAP.md`.

## Active Technologies
- Markdown (skill prompts, blueprints, intent skills), Bash (pipeline scripts — existing, no changes), YAML (GitHub Actions — existing triggers) + Auto-ref-update pipeline (001), sources.json v2, manifest.json contracts, `gh` CLI (002-scaffold-redesign)
- Git-tracked Markdown reference files in `plugins/gcore-fastedge/skills/scaffold/reference/` (002-scaffold-redesign)

- Bash (scripts), YAML (GitHub Actions workflow) + `gh` CLI (pre-installed on ubuntu-latest), `jq` (pre-installed), `claude` CLI (installed at workflow start), OpenAI gpt-4o REST API (`https://api.openai.com/v1/`) via `curl`
- `sources.json` v2 (slim pipeline config) + `manifest.json` (source-side mapping — points at docs/, no content in contract dir)
- Git annotated tags `refs/tags/ref-update/<repo-id>` (commit baselines, branchless — no committed file)
- `agent-intent-skills/<repo-id>/<filename>.md` — per-reference-file synthesis instructions injected into generator prompt
- Contract model: `fastedge-plugin-source/` in source repos contains only manifest.json + .generation-config.md (local maintenance instructions). `docs/` is single source of truth. Pipeline fetches manifest → doc paths → applies intent skills.

## Recent Changes

- **Missing intent-skill visibility** (April 2026): Pipeline now warns and labels PRs when agent-intent-skills are absent
  - `process-repos.sh`: yellow `[WARNING]` logged to stderr per mapping entry missing an intent file; `MISSING_INTENT` flag propagated to PR management
  - `manage-pr.sh`: new `missing-intent-skill` label (`e4e669`, yellow-green) added to PR when any entry lacks intent; removed on subsequent runs where all entries have intent files
  - `needs-review` label color changed from `e4e669` to `d93f0b` (red-orange) to align with error severity
  - **Tests**: 67 tests across 7 suites (was 63)
  - **PR labels**: `auto-ref-update` (blue, always), `needs-review` (red-orange, REJECT), `missing-intent-skill` (yellow-green, missing intent)

- **Pipeline v2 migration** (March 2026): Two-level config (sources.json + manifest.json)
  - `sources.json` migrated to v2 — removed `updates[]`, `sparse_paths`, added `contract_path`, `intent_dir`
  - `validate-contract.sh` — shared contract validation script (6 rules, 12 tests)
  - `generation-config-template.md` + `generate-docs-template.sh` — templates for source repos (proven from fastedge-test: sandwich output constraint, incremental updates, tiered parallel execution, table formatting)
  - Pipeline scripts read `manifest.json` target_mapping from fetched contract dir
  - `fetch-repo.sh` uses `--contract-path` (single dir) instead of `--sparse-paths` (multiple)
  - **Tests** (`scripts/sync/tests/`): 67 tests across 7 suites — all passing; run with `bash scripts/sync/tests/run-all-tests.sh`
  - **First adopter**: fastedge-test integrated end-to-end (March 2026) — 6 reference files generated, all ACCEPT from reviewer

- `001-auto-ref-update`: Full automated reference-doc sync pipeline
  - **Scripts** (`scripts/sync/`): `validate-sources.sh`, `validate-contract.sh`, `fetch-repo.sh`, `invoke-agent.sh`, `manage-pr.sh`, `process-repos.sh`
  - **Workflow** (`.github/workflows/sync-reference-docs.yml`): `workflow_dispatch` + `repository_dispatch` (`fastedge-ref-update`) triggers; per-repo failure isolation; dry_run guard
  - **Synthesis intent** (`agent-intent-skills/fastedge-test/`): per-reference-file generator shaping
