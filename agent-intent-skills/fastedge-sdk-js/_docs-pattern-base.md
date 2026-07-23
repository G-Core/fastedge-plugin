# Shared Reference Document Instructions

This file contains shared instructions for all reference document intent skills in this directory. Each intent skill references this file for universal rules.

## Audience
AI agents answering developer questions about FastEdge capabilities and usage patterns.

## Output format

Structured Markdown with **no YAML frontmatter**. Concise, decision-dense — not a tutorial. Agents use this to explain concepts and suggest code patterns.

## Cross-referencing rules

- **Never output file links or filenames** as cross-references (e.g. `[SDK_API](SDK_API.md)` or `./dotenv.md`). These reference documents live in different skill directories so relative links will not resolve.
- Instead, use **descriptive topic terms** that an agent can use to discover the relevant reference — e.g. "the SDK API reference", "the build CLI reference", "the dotenv configuration guide".
- In "See Also", "Next Steps", or "Related" sections, use plain-text topic descriptions with an em-dash explanation — e.g. `- SDK API reference — full runtime API for env, secrets, KV, and fetch`.

## Code formatting rules

- **All code blocks must use fenced code blocks** with an appropriate language tag (e.g., ` ```ts `, ` ```json `, ` ```bash `). Never include raw unfenced code — it renders poorly and is inconsistent with other reference pages.
- **Inline code containing backticks** (e.g., template literals) must use double-backtick spans (``` `` `template ${expr}` `` ```) so the inner backticks render correctly.
- Source material sections that include file contents must wrap each file in its own fenced code block with the correct language tag.

## General extraction rules

- Focus on **API usage patterns**, not project structure
- Extract idioms and patterns that help a developer understand *how* to use the capability correctly
- **Preserve exact type signatures** from authoritative sources (`.d.ts` files, type declarations). Union types (`string | null`), optional parameters, and error return types must not be simplified or omitted. When in doubt, match the type declaration verbatim.
- Include type information where available
- Content must be useful to **any AI coding tool**, not just Claude Code (MCP constraint R-007)

## Accuracy constraints

- **Type fidelity**: Return types, parameter types, and union types must exactly match the authoritative `.d.ts` declarations. Never drop `| null`, `| undefined`, or optional markers.
- **Nullability matters**: If an API returns `string | null`, the output must document both the success type and the null/not-found case. Do not simplify to just `string`.
- **Signature completeness**: Every parameter and its type must appear in documented signatures. Do not omit optional parameters or overloads that exist in the source.
- **No invented APIs**: Only document functions, methods, and properties that exist in the source. Do not infer or extrapolate APIs that are not declared.
- **Snippet validity**: Code snippets must respect documented runtime constraints. Request-time APIs (e.g., `getEnv`, `getSecret`) must be shown inside a request handler, not at module scope. Build-time APIs (e.g., `readFileSync`) must be shown at module scope. Never write a snippet that contradicts a constraint stated in the same section.

## What to exclude

- Project structure, package.json, build config (that belongs in the blueprint)
- Complete file listings
- Installation instructions
- Marketing language
