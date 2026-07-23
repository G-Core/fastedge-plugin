# Synthesis Instructions: base-rust.md

> For shared cross-referencing rules and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/base-rust.md`

## Audience
AI agents scaffolding new FastEdge CDN filter applications in Rust.

## Output goal
A base skeleton blueprint — the minimal, complete project structure an agent creates before layering any feature blueprints on top. Must contain every file needed for a working hello-world CDN proxy-wasm filter in Rust.

## Output format

YAML frontmatter followed by structured Markdown sections. Follow the base skeleton format from `specs/002-scaffold-redesign/contracts/blueprint-format.md`.

### Frontmatter (required)
```yaml
---
type: base-skeleton
app_type: cdn
languages: [rust]
template_origin: cdn-base
source_repo: <github-url>
source_ref: <commit-sha-or-tag>
updated: <YYYY-MM-DD>
---
```

### Required sections (in this order)

1. **Directory Structure** — tree of all files and directories in the project
2. **Files** — complete content of every file:
   - `Cargo.toml` — include all dependencies with exact versions, workspace declaration, `[lib]` with `crate-type = ["cdylib"]`
   - `src/lib.rs` — the proxy-wasm entry point with `RootContext`, `HttpContext`, and lifecycle hooks
   - `.cargo/config.toml` — build target (extract the exact target triple from the source example's `.cargo/config.toml` — this is the source of truth; note it may be shared at the `cdn/` level in the source repo but each project needs its own)
3. **Build Configuration** — the `cargo build --release --target <target>` command, where `<target>` matches the target triple extracted from `.cargo/config.toml`

## Extraction rules
- Extract the **complete** file contents — do not summarize or abbreviate
- The proxy-wasm lifecycle must be clearly visible: `proxy_wasm::main!`, `RootContext`, `HttpContext`, lifecycle hooks (`on_http_request_headers`, `on_http_request_body`, `on_http_response_headers`, `on_http_response_body`)
- Include dependency versions exactly as declared in Cargo.toml
- Include the `[workspace]` declaration
- The hello_world example demonstrates the minimal CDN filter — all hooks just log and continue. This is intentionally minimal so agents understand the full hook surface area without business logic noise.
- Do not add explanatory prose — this is a structural reference, not documentation

## What to exclude
- README content
- Test files or fixtures
- target/ directory or build artifacts
- Explanations of what the code does
- "When to use" guidance (that belongs in feature blueprints)
