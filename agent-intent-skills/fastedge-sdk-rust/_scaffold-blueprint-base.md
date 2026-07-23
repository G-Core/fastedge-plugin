# Shared Scaffold Blueprint Instructions

This file contains shared instructions for all feature blueprint intent skills in this directory. Each per-example intent skill references this file and adds only its example-specific details.

## Audience
AI agents scaffolding new FastEdge applications in Rust. Blueprints are consumed by the scaffold skill to assemble tailored projects.

## Output format

YAML frontmatter followed by structured Markdown sections. Follow the **feature blueprint** format from `specs/002-scaffold-redesign/contracts/blueprint-format.md`.

### Required sections (in this order)

1. **When to Use** — 1-2 sentences describing when this blueprint should be selected. The agent uses this for matching against user intent.
2. **Dependencies to Add** — Only list dependencies that are **not already in the base skeleton's Cargo.toml**. Diff the example's Cargo.toml against the base skeleton to find what is new. Do not repeat base skeleton deps here — the scaffold skill merges these on top of the base, so duplicates cause confusion about what the feature actually requires.
3. **Files to Create** — complete content of any new files this feature adds.
4. **Files to Modify** — for each existing base skeleton file that needs changes:
   - `use` statements to add
   - Code to insert into the handler, with comments indicating placement
5. **Build Notes** — any special build steps, feature flags, or caveats

### Frontmatter fields (required)

```yaml
---
type: feature
app_type: http | cdn
languages: [rust]
capabilities: [<capability-tags>]
base_skeleton: http-base | cdn-base
source_example: <repo>/<path>
source_repo: <github-url>
source_ref: <commit-sha-or-tag>
updated: <YYYY-MM-DD>
---
```

## Code formatting rules

- **All code blocks must use fenced code blocks** with an appropriate language tag (e.g., ` ```rust `, ` ```toml `, ` ```bash `). Never include raw unfenced code — it renders poorly and is inconsistent with other reference pages.
- **Inline code containing backticks** (e.g., raw strings) must use double-backtick spans so the inner backticks render correctly.
- In "Files to Create" and "Source Material" sections, wrap each file's contents in its own fenced code block with the correct language tag.

## General extraction rules

- Extract **complete** file contents for new files — do not summarize or abbreviate
- Show modifications **relative to the base skeleton** — what to add/change, not the full file
- Preserve exact API signatures, `use` paths, and type annotations
- Include dependency versions exactly as declared in Cargo.toml
- For CDN (proxy-wasm) features: show which lifecycle hook(s) the feature code goes into (`on_http_request_headers`, `on_http_request_body`, `on_http_response_headers`, `on_http_response_body`)
- Content must be useful to **any AI coding tool**, not just Claude Code (MCP constraint R-007)

## Cross-referencing rules

- **Never output file links or filenames** as cross-references (e.g. `[SDK_API](SDK_API.md)` or `./host-services-rust.md`). These reference documents live in different skill directories so relative links will not resolve.
- Instead, use **descriptive topic terms** that an agent can use to discover the relevant reference — e.g. "the SDK API reference", "the host services reference".

## What to exclude

- The base skeleton files themselves (those come from the base skeleton blueprint)
- README content
- Test files or fixtures
- target/ directory or build artifacts
- Conceptual explanations (that belongs in the docs pattern file)
