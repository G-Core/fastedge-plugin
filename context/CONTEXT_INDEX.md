# Context Index — fastedge-plugin

Start here. Read only what your task requires.

---

## Files in This Directory

| File                     | Read When                                                                                               |
| ------------------------ | ------------------------------------------------------------------------------------------------------- |
| `TEMPLATE_STRATEGY.md`   | Working on scaffold blueprints, auditing blueprint inventory, understanding the blueprint-driven model   |
| `REFERENCE_MATERIAL.md`  | Updating `fastedge-docs` reference files, adding new SDK features, understanding the sync pipeline      |
| `TDD_ROADMAP.md`         | Testing/TDD integration — what's been built, what's planned for scaffold/deploy integration             |
| `sources-json-schema.md` | Working on the sync pipeline — v2 `sources.json` schema, `manifest.json` contract schema, validation rules |
| `PIPELINE_DESIGN_DECISIONS.md` | Modifying pipeline scripts — rationale for sparse checkout, baseline tags, fail-visible, agent choices |
| `AGENT_CONTRACTS.md`    | Modifying `invoke-agent.sh` or workflow triggers — generator/reviewer/splice interfaces, trigger payloads |
| `AUTHORING_GUIDELINES.md` | Authoring or modifying reference docs, intent skills, blueprints, or pattern docs — verification rules, terminology, CDN ruleset semantics, source-of-truth boundaries |
| `REFERENCE_DOCS_AUDIT_HANDOFF.md` | **In-flight cleanup** — picking up the April 2026 reference-docs audit after source-repo PRs merge. Pipeline run, orphan deletion, SKILL.md update, SDK_API extension. Delete the file once all checklist items are confirmed done |
| `NEXT_PRIORITIES.md`   | **Forward queue (2026-05-20)** — three prioritized items: post-merge pipeline run, audit close-out, MCP directory listings. Delete the file once all remaining items are done |
| `MCP_INTEGRATION.md`   | Modifying deploy/manage/scaffold skills, onboarding source repos, adding reference material — planned MCP server integration affects all of these |
| `PLUGIN_DISTRIBUTION.md` | Repo structure, marketplace descriptors (Claude + Codex), install commands per runtime, release cadence — read before touching distribution, marketplace files, or cross-runtime concerns |
| `REFERENCE_ARTIFACT_PIPELINE.md` | **Planned work** — 8-task plan to mirror reference docs into Codex plugin, emit two `docs-index.json` files, package + attach a tarball to the GitHub Release, wire the MCP server consumer. Read alongside `PLUGIN_DISTRIBUTION.md` |

---

## Key Decisions Already Made

| Decision                                     | Summary                                                                                                | Detail                                  |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------- |
| proxy-wasm-sdk-as integrated as source repo  | 4th source repo added to pipeline (April 2026). CDN-only AS SDK. 20 intent files, 16 manifest entries. Critical: hook state isolation (context per-hook, not per-request), unsupported features omitted entirely. | `REFERENCE_MATERIAL.md`, `sources.json`, `agent-intent-skills/proxy-wasm-sdk-as/` |
| Scaffold uses blueprint-driven model         | The scaffold skill creates projects from blueprint reference files in `skills/scaffold/reference/`, not by delegating to `create-fastedge-app` CLI | `TEMPLATE_STRATEGY.md`, `specs/002-scaffold-redesign/` |
| Blueprints are pipeline-generated            | The auto-ref-update pipeline processes SDK example repos with dual-intent skills, producing blueprint files (for scaffold) and pattern files (for docs) | `TEMPLATE_STRATEGY.md`, `specs/002-scaffold-redesign/contracts/` |
| create-fastedge-app not onboarded            | Remains a human-facing npm tool only. SDK repos (FastEdge-sdk-js, FastEdge-sdk-rust) provide all blueprint source material | `TEMPLATE_STRATEGY.md` |
| Seed blueprints hand-crafted for MVP         | 12 initial blueprints (4 base skeletons + 8 features) created from source examples. Will be replaced by pipeline-generated versions | `skills/scaffold/reference/` |
| Blueprint format uses YAML frontmatter       | Each blueprint has typed metadata (type, app_type, languages, capabilities) for agent-driven matching    | `specs/002-scaffold-redesign/contracts/blueprint-format.md` |
| Dual-intent pipeline processing              | Same source example processed twice: scaffold intent → blueprint, docs intent → pattern. Config-only, no script changes | `specs/002-scaffold-redesign/research.md` R-001 |
| Smart-skip intake flow                       | Scaffold skill infers feature intent from initial request when present; only asks "What does this app need to do?" for bare requests | `skills/scaffold/SKILL.md` Step 2 |
| mcp-server skill removed                     | Was in the original README, never implemented. Add to `create-fastedge-app` first if needed            | —                                       |
| Reference files are embedded                 | Docs are in `reference/*.md` in the plugin, not fetched from Context7 or live URLs at runtime          | `REFERENCE_MATERIAL.md`                 |
| Reference sync is automated via v2 pipeline  | Two-stage generation: source contract → manifest-driven pipeline. `sources.json` v2 (slim config) + `manifest.json` (content mapping) | `REFERENCE_MATERIAL.md`, `sources-json-schema.md` |
| scaffold `disable-model-invocation: false`   | Changed so agents can invoke the scaffold skill directly (not just users via slash command)            | —                                       |
| File system scope is a hard constraint       | Agents are explicitly prohibited from reading `../` paths or sibling folders                           | `plugins/gcore-fastedge/CLAUDE.md`      |
| Intake-first protocol                        | Agents must collect app type → language → name before any research or file operations                  | `plugins/gcore-fastedge/CLAUDE.md`      |
| JS runtime constraints documented            | StarlingMonkey constraints, crypto.subtle matrix, SAML incompatibilities — in `js-runtime.md`          | `REFERENCE_MATERIAL.md`                 |
| sources.json migrated to v2                  | Removed `updates[]`, `sparse_paths`. Added `contract_path`, `intent_dir`. Content mapping in manifest. | `sources-json-schema.md`                |
| Contract validation is shared infrastructure | `validate-contract.sh` runs in source repo CI + plugin pipeline. 6 rules, advisory/strict modes.       | `sources-json-schema.md`                |
| Generation config template exists            | `scripts/sync/templates/generation-config-template.md` — source repos copy and customize               | `REFERENCE_MATERIAL.md`                 |
| Sync pipeline uses `gh api` for URL checks   | Rule 2 in `validate-sources.sh` uses `gh api repos/:owner/:repo` — supports private repos via SAML     | `sources-json-schema.md`                |
| Pipeline auth via GitHub App                 | `fastedge-plugin-sync` App generates short-lived tokens — no PAT, no developer blocked from PR review  | `REFERENCE_MATERIAL.md`                 |
| Baseline tracking via annotated git tags     | `refs/tags/ref-update/<repo-id>` — branchless, no commit needed, last-writer-wins on concurrent runs   | `PIPELINE_DESIGN_DECISIONS.md`, `REFERENCE_MATERIAL.md` |
| Agent-toolkit doctor installed               | 4 workflow files in `.github/workflows/`. Needs secrets (D02) + first run (D03) to complete setup.     | `.github/workflows/doctor.yml`          |
| docs/ structure follows doctor standard      | `docs/INDEX.md` (entry point) + `docs/quickstart.md` (onboarding). Required by doctor compliance.     | `docs/INDEX.md`                         |
| .gitignore follows doctor policy             | `.codex`, `.claude`, `.specify`, `specs/*` ignored; `.specify/memory/constitution.md` tracked via negation | `.gitignore`                        |
| Plugin delegates build/deploy to MCP server  | Phase 1: deploy skill calls MCP `build-wasm` + `upload-binary` + `update-or-create-app` instead of direct shell/API. Fallback to local if MCP unavailable. Plugin keeps workflow orchestration. | `MCP_INTEGRATION.md` |
| Phase 2 (docs as MCP resources) dropped      | The `fastedge-docs` tool already provides search/read access to all reference docs. MCP resources would duplicate this with worse UX and risk context pollution. Non-Claude tools use the tool. | `MCP_INTEGRATION.md` |
| Blueprint format is the long-term contract   | YAML frontmatter in blueprints will be consumed by plugin and other AI tools via MCP server. Keep metadata clean and generic — no plugin-specific fields. | `MCP_INTEGRATION.md` |
| Reference docs use topic terms, not file links | Generated reference docs must never contain file links or filenames as cross-references — reference docs live in different skill directories so relative links don't resolve. Use descriptive topic terms agents can search for. Enforced via `_docs-pattern-base.md` in each intent dir. | `REFERENCE_MATERIAL.md` (Synthesis Intent Files) |
| API key is `GCORE_API_KEY` everywhere          | MCP server accepts `GCORE_API_KEY` (preferred) with `FASTEDGE_API_KEY` fallback for backward compat. All docs, configs, and skills use `GCORE_API_KEY` as primary. | `MCP_INTEGRATION.md` (Decision Log) |
| Docs-index staged after reference file check   | `write_and_push()` stages reference files first, checks for changes, then regenerates/stages `docs-index.json` only if content changed. Prevents `generated_at` timestamp from defeating the no-changes early exit. | `PIPELINE_DESIGN_DECISIONS.md` §8 |
| Intent skills use hierarchical inheritance   | Root base files (`_docs-pattern-base.md`, `_scaffold-blueprint-base.md`) contain universal rules. Subdirectory bases (`http/_docs-pattern-http.md`, `cdn/_scaffold-blueprint-cdn.md`) inherit from root and add appType-specific structure. Prevents root-level intent skills from missing universal rules. | `REFERENCE_MATERIAL.md` (Synthesis Intent Files) |

---

## What to Read For...

| Task                                     | Read                                                                            |
| ---------------------------------------- | ------------------------------------------------------------------------------- |
| Working on scaffold blueprints           | `TEMPLATE_STRATEGY.md`, `specs/002-scaffold-redesign/contracts/blueprint-format.md` |
| Adding/updating scaffold capabilities    | `TEMPLATE_STRATEGY.md` (blueprint inventory table)                              |
| Updating docs reference content          | `REFERENCE_MATERIAL.md`                                                         |
| Testing integration                      | `TDD_ROADMAP.md`, `skills/test/SKILL.md`                                        |
| Agent behaviour / interaction protocol   | `plugins/gcore-fastedge/CLAUDE.md` — Interaction Protocol section               |
| JS runtime limits, SAML, crypto.subtle   | `plugins/gcore-fastedge/skills/fastedge-docs/reference/js-runtime.md`           |
| Working on the sync pipeline             | `REFERENCE_MATERIAL.md`, `sources-json-schema.md`, `PIPELINE_DESIGN_DECISIONS.md`, `AGENT_CONTRACTS.md` |
| Adding a new source repo to the pipeline | `sources-json-schema.md` (see "How to Add a New Source Repo" section), `MCP_INTEGRATION.md` (manifest output targets) |
| Modifying deploy or manage skills        | `MCP_INTEGRATION.md` (isolate API calls from orchestration — Phase 1 replaces API calls) |
| Adding reference material                | `REFERENCE_MATERIAL.md`, `MCP_INTEGRATION.md` (content must be self-contained — consumed by both plugin and MCP `fastedge-docs` tool) |
| Working on Codex plugin implementation   | `plugins/gcore-fastedge-codex/` directly + `docs/codex-quickstart.md` (Codex plugin is feature-complete as of 2026-05-20 — alignment + worked examples landed; no separate status doc) |
| Touching marketplace files / install docs | `PLUGIN_DISTRIBUTION.md` — both marketplaces + how users install per runtime |
| Modifying `release-plugin.yml` or pipeline outputs | `REFERENCE_ARTIFACT_PIPELINE.md` — planned changes to make reference docs flow to all three consumers |
| Doctor compliance / agent standards      | `.github/workflows/doctor.yml`, `.github/workflows/collect.py`                  |
| User-facing documentation                | `docs/INDEX.md`, `docs/quickstart.md`                                           |
| 002-scaffold-redesign feature details    | `specs/002-scaffold-redesign/` (spec, plan, research, contracts, tasks)          |

---

## Known Gaps (Future Work)

- `fastedge-docs/reference/best-practices.md` and `error-codes.md` — may still be stubs, review needed
- `sdk-reference-js.md`, `sdk-reference-rust.md`, and `platform-overview.md` — have real content (not stubs)
- Deploy skill: pre-deploy test step added (Step 1.5), `--skip-tests` override added (April 2026)
- Scaffold skill: post-scaffold offers both `/test` and `/debug` independently (April 2026)
- `/debug` skill created (April 2026) — generates `fixtures/` with scenario configs for visual debugger
- Testing FAQ in best-practices reference — not yet added
- AssemblyScript CDN app capabilities in `CLAUDE.md` were verified against `proxy-wasm-sdk-as/assembly/fastedge/kvStore.ts` — KvStore is **read-only** (no set/write), `open()` returns `KvStore | null`, `get()` returns `ArrayBuffer | null`
- Doctor setup incomplete — secrets (PL-D02) and first run (PL-D03) still needed. After first run, `AGENTS.md`, `DOCS.md`, and `.toolkit/` will be created automatically.

### Post-Onboarding Cleanup

- **`sources.json`: fastedge-sdk-js and fastedge-sdk-rust refs are temporarily `"main"`** — changed from `"latest-release"` during onboarding because the `fastedge-plugin-source/` contracts didn't exist at the latest tagged releases. Once contracts are merged and new releases are cut, reset both to `"latest-release"` so doc syncs are release-gated.
- **`sources.json`: proxy-wasm-sdk-as ref is `"latest-release"`** — added April 2026. Pipeline test (AS-07) pending. Deploy workflow dispatch (AS-09) not yet wired.

### MCP Integration — Planned (after 002-scaffold-redesign)

Build/deploy delegation to FastEdge-mcp-server. Phase 1 (delegate build + deploy API calls) complete. Phase 2 (reference docs as MCP resources) dropped — `fastedge-docs` tool is sufficient. Phase 3 (blueprint metadata in MCP) planned. See `MCP_INTEGRATION.md`.

### 002-scaffold-redesign — Complete

**Summary**: Scaffold skill rewritten to blueprint-driven model. Pipeline generates blueprints from SDK examples (FastEdge-sdk-js, FastEdge-sdk-rust). All knowledge base files updated to reflect blueprint model. Plugin version bumped to 0.1.0.

**Key artifacts:**
- Scaffold SKILL.md: 5-step blueprint-driven flow (intake → intent detection → blueprint selection → assembly → next steps)
- 13 blueprints in `skills/scaffold/reference/` (4 base skeletons + 9 features), pipeline-generated from SDK repos. proxy-wasm-sdk-as will add 6 more (1 base + 5 features) when pipeline runs.
- Intent skills with hierarchical inheritance: root bases → appType bases → per-example files. 4th intent directory added for proxy-wasm-sdk-as (20 files).
- Pipeline PRs merged for all 3 source repos (fastedge-test #35, fastedge-sdk-js #34, fastedge-sdk-rust #33/#36). proxy-wasm-sdk-as pending first run (AS-07).
- Blueprint format contract: `specs/002-scaffold-redesign/contracts/blueprint-format.md`
- Dual-intent manifest pattern: `specs/002-scaffold-redesign/contracts/manifest-dual-intent.md`

**Note:** `sources.json` refs for fastedge-sdk-js and fastedge-sdk-rust are still `"main"` — reset to `"latest-release"` once new releases are cut.
