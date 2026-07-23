# MCP Integration — Plugin + FastEdge MCP Server

**Status:** Phase 1 complete (2026-04-10). Phases 2-3 planned.
**Decision date:** 2026-04-07, updated 2026-04-10
**Depends on:** 002-scaffold-redesign (complete), source repo onboarding (complete)

---

## Why This Matters — Read This First

The fastedge-plugin and FastEdge-mcp-server currently duplicate build and deploy logic. Both shell out to the same compilers, both call the same FastEdge REST API. This duplication will cause bugs and maintenance burden as both projects evolve.

**Every change to the plugin should be made with this integration in mind.** When adding capabilities, modifying skills, or onboarding source repos — ask: "Does this belong in the plugin's intelligence layer or the MCP server's execution layer?"

---

## Architecture Decision: Layered Responsibility Model

```
+-------------------------------------+
|         Claude Plugin               |  Intelligence + Orchestration
|                                     |
|  - Blueprint selection & composition|  (WHAT to build)
|  - SDK reference / docs             |
|  - Intent detection & guidance      |
|  - Test orchestration               |
|  - Workflow orchestration            |
|  - Pre-deploy validation            |
+----------------+--------------------+
                 | MCP protocol (tool calls)
                 v
+-------------------------------------+
|         MCP Server                  |  Execution + Environment
|                                     |
|  - Build (Rust/JS/AS in Docker)     |  (HOW to execute)
|  - Deploy (API integration)         |
|  - Binary management                |
|  - Env var / secret management      |
|  - Reference material (via fastedge-docs tool)|
+-------------------------------------+
```

**Plugin = knows WHAT to build.** Blueprint-driven scaffolding, SDK reference, best practices, intent detection, workflow orchestration, user interaction.

**MCP Server = knows HOW to execute.** Containerized build environment (Rust 1.90, Node 24, wasm32-wasip1), FastEdge API gateway, binary management, environment/secrets.

---

## Current Overlap (as of 2026-04-07)

| Capability | Plugin (today) | MCP Server (today) | Target owner |
|---|---|---|---|
| **Build** | Shells out to `fastedge-build`, `cargo build` directly | Dockerized `build-wasm` tool with pre-installed toolchains | **MCP Server** |
| **Deploy (API calls)** | Direct REST calls to `api.gcore.com/fastedge/v1` | Same REST calls via `upload-binary`, `update-or-create-app` | **MCP Server** |
| **Deploy (workflow)** | Pre-deploy checks, user confirmation, test-before-deploy | Basic build-upload-deploy prompt | **Plugin** |
| **Scaffold** | Blueprint-driven: 4 base + 8 feature, composable, agent-assembled | Template-driven: delegates to `create-fastedge-app`, 4 templates | **Plugin** (intelligence), MCP Server (baseline) |
| **Manage** | Full CRUD + secrets + env sync | Partial (upload, create/update, env vars) | **Both** (plugin orchestrates, MCP executes) |
| **Test** | Full `@gcoredev/fastedge-test` integration | None | **Plugin** |
| **Reference docs** | 5 categories: SDK, best practices, error codes, platform, JS runtime | `fastedge-docs` tool (topics/search/read) + 2 guide resources | **Both** (plugin embeds, MCP serves via `fastedge-docs` tool) |

---

## Integration Phases

### Phase 1: Delegate Build + Deploy to MCP Server

**Priority:** High — eliminates the largest duplication and solves the "user must install Rust toolchain" problem.

**What changes in the plugin:**

1. **Deploy skill** (`skills/deploy/SKILL.md`): Replace direct `fastedge-build` / `cargo build` commands with MCP server's `build-wasm` tool call. Replace direct REST API calls with MCP server's `upload-binary` + `update-or-create-app` + `update-env-vars-app`.

2. **Plugin retains workflow orchestration:** Pre-deploy test check (TDD_ROADMAP.md), user confirmation flow, validation, error handling, Magic Comments generation.

3. **Local-toolchain opt-out:** The MCP server is the default execution path; both `gcore-fastedge` and `gcore-fastedge-codex` ship `.mcp.json` files that register it on install. A local-toolchain path remains for developers who explicitly decline Docker, but skills should not auto-fall-back silently — they warn, ask, and proceed only on user confirmation.

4. **Manage skill** (`skills/manage/SKILL.md`): Delegate API calls to MCP server tools where overlap exists. Plugin keeps the subcommand routing and user interaction.

**What changes in the MCP server:**
- Nothing in Phase 1. The tools already exist.

**Phase 1 completed (2026-04-10):**
- Deploy skill rewritten: MCP tools are primary, local commands are fallback
- Manage skill rewritten: MCP tools used for covered operations, direct API for gaps (delete, list secrets, stats)
- MCP unavailability triggers user-facing warning with setup instructions and option to fall back to local
- Magic Comments format aligned with MCP server's `deployment-comments` tool output
- 3 MCP gaps identified (delete app, list secrets, app stats) — deferred to Phase 6 (Code Mode)

### ~~Phase 2: Reference Material as MCP Resources~~ — DROPPED

**Status:** Dropped (2026-04-14). The `fastedge-docs` tool in the MCP server already provides topics/search/read access to all reference docs. Adding the same content as MCP resources would duplicate what the tool does, with worse UX (no search, no excerpts) and risk polluting the context window in clients that auto-inject resources.

**Rationale:** MCP resources are static blobs — the agent reads the whole document. The `fastedge-docs` tool lets agents search by keyword and get focused excerpts, which is strictly better for reference material. Non-Claude/non-Codex environments should use the `fastedge-docs` tool for discovery and retrieval.

**What remains:** The two existing scaffolding guide resources (`fastedge://guides/scaffolding`, `fastedge://guides/templates`) stay — they're small, workflow-specific guides, not searchable reference material.

### Reference-Docs Distribution Artifact (planned, separate from Phase 2)

**Status:** Plan, not yet implemented. See `REFERENCE_ARTIFACT_PIPELINE.md` for the full task list.

**What it is — and isn't:** This is **not** a revival of dropped Phase 2. Phase 2 was about exposing reference docs *as MCP resources* (a runtime interface). This is about how the MCP server **gets the reference content into its Docker image** at build time. Once the content is inside the image, the existing `fastedge-docs` MCP tool serves it — that surface doesn't change.

**Pipeline shape:**
1. `fastedge-plugin` weekly release workflow produces a tarball `fastedge-reference-docs-vX.Y.Z.tar.gz` and attaches it to the GitHub Release.
2. The release workflow `repository_dispatch`es to `FastEdge-mcp-server` with `event_type: plugin-release` and a payload containing the tag, version, and artifact download URL.
3. On the MCP server side, a workflow listens for that dispatch, downloads + verifies the tarball, extracts it into `vendor/fastedge-reference-docs/`, and opens a PR bumping the pinned version.
4. Merging that PR triggers the existing MCP server image rebuild. New `:latest` tag includes the new docs.

**Why this matters for MCP-server design:**
- The MCP server's `fastedge-docs` tool reads `docs-index.json` + reference markdown from a fixed local path. That path becomes `vendor/fastedge-reference-docs/` (relative to repo root inside the container).
- The tarball's internal docs-index has paths rewritten to be relative to the artifact root (`reference/...`), so the MCP server tool doesn't need path math — it concatenates `vendor/fastedge-reference-docs/` + the index path.
- The MCP server image rebuilds **only when reference docs change** (weekly cadence at most, often less). Plugin merges that don't change reference content do not trigger rebuilds.

**Versioning contract:** the MCP server pins to the same `vX.Y.Z` as the plugins. One version number across all three consumers. No semver drift to reason about.

See `REFERENCE_ARTIFACT_PIPELINE.md` (this repo) for the implementation tasks. The MCP server consumer workflow lives in `FastEdge-mcp-server` — see Task 8 in that doc.

### Phase 3: Blueprint Resources in MCP Server (longer-term)

**Priority:** Medium — benefits non-Claude AI tool users.

**What changes:**

1. **MCP server exposes blueprint metadata** via a tool or MCP resources (blueprint frontmatter: type, app_type, languages, capabilities). Resource vs. tool decision TBD — resources may be appropriate here since blueprints are small metadata, unlike reference docs.

2. **Optionally:** MCP server gets a `scaffold-from-blueprint` tool that accepts a blueprint spec (base + features list) and produces a project. The plugin still does intent detection and blueprint selection — MCP server handles assembly.

3. **MCP server's existing `scaffold-fastedge-project`** continues using `create-fastedge-app` as the baseline experience. Blueprint-driven scaffolding is the premium layer.

**Impact on 002-scaffold-redesign:**
- Blueprint format (`specs/002-scaffold-redesign/contracts/blueprint-format.md`) should remain stable and machine-readable — it will eventually be consumed by both the plugin and other AI tools via the MCP server.
- The YAML frontmatter metadata in blueprints is the contract. Don't add plugin-specific fields that wouldn't make sense as MCP resource metadata.

---

## Design Constraints

### Context size
The MCP server currently exposes 10 tools + 4 prompts + 2 resources. Delegating build/deploy from the plugin does NOT increase MCP tool count — those tools already exist. Reference docs are served via the `fastedge-docs` tool (not as MCP resources) to avoid context bloat from clients that auto-inject resources.

### Independence
The MCP server is independently deployable and works without the plugin (other AI tools, CLI usage). The plugin is **not** standalone — it ships `.mcp.json` and assumes MCP-as-executor for build/deploy/manage. A local-toolchain opt-out exists for developers who decline Docker, but it's an explicit choice, not the default.

### Docker dependency
Docker is a hard requirement for the default install path (the plugin auto-loads `.mcp.json` which spawns the FastEdge MCP server image). The local-toolchain opt-out is the escape hatch for users who can't or won't run Docker — it stays functional but is unsupported in the sense that we no longer optimize for it.

---

## What This Means For Current Work

### When completing 002-scaffold-redesign:
- Blueprint format is the long-term contract. Keep frontmatter metadata clean and generic.
- Scaffold skill should NOT include build/deploy commands inline — reference the deploy skill instead. This keeps the separation clean for Phase 1.

### When onboarding source repos to the pipeline:
- Design `manifest.json` with awareness that output feeds both plugin reference files AND (future) MCP server resources.
- Intent skills should produce content useful to any AI coding tool, not just Claude Code.

### When modifying the deploy skill:
- Isolate API call logic from workflow orchestration logic. Phase 1 replaces the API calls, keeps the orchestration.
- Document which API endpoints are called and with what parameters — this maps directly to MCP server tools.

### When modifying the manage skill:
- Same principle: isolate API calls from user interaction flow.

### When adding new reference material:
- Content is automatically available in the MCP server via the `fastedge-docs` tool (synced from `docs-index.json`). Ensure content is self-contained (no plugin-specific context references).

---

## MCP Server Current Capabilities (snapshot 2026-04-07)

For reference when planning integration points:

**Tools:** `build-wasm`, `upload-binary`, `update-or-create-app`, `update-env-vars-app`, `get-secret-id`, `scaffold-fastedge-project`, `deployment-comments`

**Prompts:** `createFastEdgeApp`, `deployFastEdgeApp`, `setEnvironmentVariables`, `insertMagicComments`, `explainFastEdgeTemplate`

**Resources:** `fastedge://guides/scaffolding`, `fastedge://guides/templates`

**Docker environment:** Rust 1.90-slim, Node 24, pnpm 10, wasm32-wasip1 target. Workspace mounted at `/workspace`.

**API base:** `GCORE_API_BASE` overrides the host (default: `https://api.gcore.com`; preprod: `https://api.preprod.world`). The MCP server appends `/fastedge/v1` itself.

**Auth:** `GCORE_API_KEY` environment variable (legacy `FASTEDGE_API_KEY` also accepted)

---

## Decision Log

| Date | Decision | Rationale |
|---|---|---|
| 2026-04-07 | Plugin delegates build/deploy to MCP server (Phase 1) | Eliminates duplication; MCP server has containerized toolchains; single API integration point |
| 2026-04-07 | Plugin retains scaffold intelligence | Blueprint-driven model (002) is far superior to template-driven; composability is the plugin's core value |
| 2026-04-07 | ~~MCP server gets reference docs as resources (Phase 2)~~ | ~~Non-Claude AI tool users need guidance; MCP resources are pull-based (no context bloat)~~ |
| 2026-04-14 | Phase 2 dropped — `fastedge-docs` tool is sufficient | The tool provides search + excerpts, which is better than static resource blobs for reference material. Resources risk context pollution in clients that auto-inject. |
| 2026-04-07 | Fallback-to-local pattern for builds | Plugin must work without Docker/MCP server, just with degraded experience |
| 2026-04-07 | Both projects remain independently deployable | No hard coupling; integration enhances but isn't required |
| 2026-04-14 | API key aligned to `GCORE_API_KEY` across plugin + MCP server | Two names for the same key (`FASTEDGE_API_KEY` vs `GCORE_API_KEY`) was bad DX. MCP server now prefers `GCORE_API_KEY` with `FASTEDGE_API_KEY` fallback for backward compat. All docs/configs updated. |
| 2026-05-20 | Reference docs ship to MCP server as GitHub Release tarball + repository_dispatch | Decouples MCP image rebuild from plugin-merge cadence; pins MCP to the same `vX.Y.Z` as plugins; consumer-side PR review preserves human control of when MCP image gets a new docs payload. Not a revival of Phase 2 — this is build-time content delivery, not runtime MCP resources. See `REFERENCE_ARTIFACT_PIPELINE.md`. |
