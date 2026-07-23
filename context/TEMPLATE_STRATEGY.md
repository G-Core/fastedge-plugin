# Blueprint Strategy — Scaffold Skill

## Design Decision: Blueprint-Driven Scaffolding (002-scaffold-redesign)

The scaffold skill (`plugins/gcore-fastedge/skills/scaffold/SKILL.md`) creates projects from blueprint reference files in `skills/scaffold/reference/`, replacing the previous model of delegating to `create-fastedge-app`.

### Why Blueprints

1. **Richer output** — SDK example repos contain 24+ examples demonstrating specific capabilities (KV Store, A/B testing, JWT auth, geoblocking, etc.). Blueprints derived from these examples produce feature-specific projects vs the old 4 generic CLI templates.

2. **Composable** — Feature blueprints layer on top of base skeletons. A user asking for "HTTP app with KV Store" gets both the base structure AND KV-specific code, imports, and dependencies wired together.

3. **Pipeline-maintained** — The auto-ref-update pipeline generates blueprints from SDK example repos via dual-intent processing. When examples change, blueprints update via PR. No manual sync needed.

4. **Language-adaptive** — A TypeScript-sourced blueprint covers both TS and JS output. The agent adapts type annotations and build config at scaffold time.

### Blueprint Types

| Type | Source | Purpose |
|------|--------|---------|
| Base skeleton | SDK hello-world / starter examples | Foundational project structure (directory layout, package manifest, build config, entry point) |
| Feature blueprint | SDK feature examples | Capability-specific patterns layered on top of a base skeleton |

### Source Repos (Pipeline)

| Repo | Provides | Status |
|------|----------|--------|
| FastEdge-sdk-js | JS/TS base skeleton + feature blueprints (KV Store, A/B testing, fetch, headers, geo-redirect) | Live — pipeline runs merged (PRs #34), reference files generated |
| FastEdge-sdk-rust | Rust HTTP WASI + CDN base skeletons + feature blueprints (KV Store, JWT auth, geoblock, body) — examples at `examples/cdn/`, `examples/http/wasi/` (http/basic/ is legacy) | Live — pipeline runs merged (PRs #33, #36), reference files generated |
| proxy-wasm-sdk-as | AssemblyScript CDN base skeleton + feature blueprints | Future |

`create-fastedge-app` is **not** onboarded — it remains a human-facing npm tool only, invisible to agents.

### Blueprint Format

Each blueprint is a Markdown file with YAML frontmatter for agent-readable metadata:

```yaml
---
type: base-skeleton | feature
app_type: http | cdn
languages: [typescript, javascript] | [rust] | [assemblyscript]
capabilities: [kv-store]          # feature blueprints only
base_skeleton: http-base           # feature blueprints only
source_example: <repo>/<path>      # feature blueprints only
---
```

See `specs/002-scaffold-redesign/contracts/blueprint-format.md` for the authoritative format specification.

### How to Audit Blueprints

Blueprints are pipeline-generated from SDK example repos. To verify they're current:

1. Check blueprint frontmatter for `source_repo` and `source_ref`
2. Compare against the current state of the source example
3. If stale, trigger the pipeline: `gh workflow run sync-reference-docs.yml -f source_repo_id=<repo-id>`

### Seed Blueprints (Historical)

The initial set of 12 seed blueprints were hand-crafted during the MVP phase. Pipeline-generated versions from FastEdge-sdk-js and FastEdge-sdk-rust have replaced all JS/TS and Rust seeds. Only `cdn/base-as.md` remains as a hand-crafted seed (no AS source repo onboarded yet).

### Current Blueprint Inventory

| Blueprint | Type | App Type | Languages | Source |
|-----------|------|----------|-----------|--------|
| `http/base-ts.md` | base-skeleton | HTTP | TS, JS | Pipeline-generated from FastEdge-sdk-js |
| `http/base-rust.md` | base-skeleton | HTTP | Rust | Pipeline-generated from FastEdge-sdk-rust |
| `cdn/base-rust.md` | base-skeleton | CDN | Rust | Pipeline-generated from FastEdge-sdk-rust |
| `cdn/base-as.md` | base-skeleton | CDN | AS | Hand-crafted seed (no AS source repo onboarded yet) |
| `http/kv-store-ts.md` | feature | HTTP | TS, JS | FastEdge-sdk-js/examples/kv-store |
| `http/ab-testing-ts.md` | feature | HTTP | TS, JS | FastEdge-sdk-js/examples/ab-testing |
| `http/fetch-ts.md` | feature | HTTP | TS, JS | FastEdge-sdk-js/examples/downstream-fetch |
| `http/headers-ts.md` | feature | HTTP | TS, JS | FastEdge-sdk-js/examples/headers |
| `http/geo-redirect-ts.md` | feature | HTTP | TS, JS | FastEdge-sdk-js/examples/geo-redirect |
| `http/kv-store-rust.md` | feature | HTTP | Rust | FastEdge-sdk-rust/examples/http/wasi/key_value |
| `cdn/auth-jwt-rust.md` | feature | CDN | Rust | FastEdge-sdk-rust/examples/cdn/jwt |
| `cdn/geoblock-rust.md` | feature | CDN | Rust | FastEdge-sdk-rust/examples/cdn/geoblock |
| `cdn/body-rust.md` | feature | CDN | Rust | FastEdge-sdk-rust/examples/cdn/body |
