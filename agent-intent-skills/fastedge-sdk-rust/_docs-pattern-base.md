# Shared Reference Document Instructions

This file contains shared instructions for all reference document intent skills in this directory. Each intent skill references this file for universal rules.

## Audience
AI agents answering developer questions about FastEdge capabilities and usage patterns in Rust.

## Output format

Structured Markdown with **no YAML frontmatter**. Concise, decision-dense — not a tutorial. Agents use this to explain concepts and suggest code patterns.

## Cross-referencing rules

- **Never output file links or filenames** as cross-references (e.g. `[SDK_API](SDK_API.md)` or `./host-services-rust.md`). These reference documents live in different skill directories so relative links will not resolve.
- Instead, use **descriptive topic terms** that an agent can use to discover the relevant reference — e.g. "the SDK API reference", "the host services reference".
- In "See Also", "Next Steps", or "Related" sections, use plain-text topic descriptions with an em-dash explanation — e.g. `- Host services reference — KV store, secrets, and dictionary APIs`.

## Code formatting rules

- **All code blocks must use fenced code blocks** with an appropriate language tag (e.g., ` ```rust `, ` ```toml `, ` ```bash `). Never include raw unfenced code — it renders poorly and is inconsistent with other reference pages.
- **Inline code containing backticks** (e.g., template literals or raw strings) must use double-backtick spans so the inner backticks render correctly.
- Source material sections that include file contents must wrap each file in its own fenced code block with the correct language tag.

## General extraction rules

- Focus on **API usage patterns**, not project structure
- Extract idiomatic Rust patterns (Result handling, borrowing, error propagation with `?`)
- For CDN patterns: note which proxy-wasm lifecycle hooks are involved
- **Preserve exact type signatures** from authoritative sources (Rust type definitions, trait signatures). `Option<T>`, `Result<T, E>`, lifetime annotations, and generic bounds must not be simplified or omitted. When in doubt, match the type declaration verbatim.
- Include type information where available
- Content must be useful to **any AI coding tool**, not just Claude Code (MCP constraint R-007)

## Accuracy constraints

- **Type fidelity**: Return types, parameter types, and generic bounds must exactly match the authoritative Rust type definitions. Never drop `Option<T>`, `Result<T, E>`, or lifetime annotations.
- **Nullability matters**: If an API returns `Option<Vec<u8>>`, the output must document both the `Some` case and the `None`/not-found case. Do not simplify to just `Vec<u8>`.
- **Signature completeness**: Every parameter and its type must appear in documented signatures. Do not omit trait bounds, error types, or overloads that exist in the source.
- **No invented APIs**: Only document functions, methods, and traits that exist in the source. Do not infer or extrapolate APIs that are not declared.
- **Import alias consistency**: When the imports section aliases a type (e.g., `use foo::Error as FooError`), all subsequent signatures and prose must use the aliased name (`FooError`), not the original. Mixing both creates confusion about whether they are distinct types.
- **Snippet validity**: Code snippets must respect documented runtime constraints and lifecycle rules. For example, request-time APIs must be shown inside a handler function, not at module scope. Never write a snippet that contradicts a constraint stated in the same section.

## What to exclude

- Project structure, Cargo.toml, build config (that belongs in the blueprint)
- Complete file listings
- Installation instructions
- Marketing language
