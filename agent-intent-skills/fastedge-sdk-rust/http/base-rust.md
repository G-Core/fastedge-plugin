# Synthesis Instructions: base-rust.md

> For shared cross-referencing rules and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/base-rust.md`

## Audience
AI agents scaffolding new FastEdge HTTP applications in Rust.

## Output goal
A base skeleton blueprint — the minimal, complete project structure an agent creates before layering any feature blueprints on top. Must contain every file needed for a working hello-world HTTP WASI app in Rust.

## Output format

YAML frontmatter followed by structured Markdown sections. Follow the base skeleton format from `specs/002-scaffold-redesign/contracts/blueprint-format.md`.

### Frontmatter (required)
```yaml
---
type: base-skeleton
app_type: http
languages: [rust]
template_origin: http-base
source_repo: <github-url>
source_ref: <commit-sha-or-tag>
updated: <YYYY-MM-DD>
---
```

### Required sections (in this order)

1. **Directory Structure** — tree of all files and directories in the project
2. **Files** — complete content of every file:
   - `Cargo.toml` — include all dependencies with exact versions, workspace declaration, `[lib]` with `crate-type = ["cdylib"]`
   - `src/lib.rs` — the entry point with `#[fastedge::http]` or WASI handler
   - `.cargo/config.toml` — build target (extract the exact target triple from the source example's `.cargo/config.toml` — this is the source of truth and varies per example)
3. **Build Configuration** — the `cargo build --release --target <target>` command, where `<target>` matches the target triple extracted from `.cargo/config.toml`

## Extraction rules
- Extract the **complete** file contents — do not summarize or abbreviate
- Include dependency versions exactly as declared in Cargo.toml
- The entry point pattern and handler signature must be preserved exactly
- Include the `[workspace]` declaration (single-project workspace pattern used by examples)
- Do not add explanatory prose — this is a structural reference, not documentation

## What to exclude
- README content
- Test files or fixtures
- target/ directory or build artifacts
- Explanations of what the code does
- "When to use" guidance (that belongs in feature blueprints)
