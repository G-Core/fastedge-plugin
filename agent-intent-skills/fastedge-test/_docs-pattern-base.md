# Shared Reference Document Instructions

This file contains shared instructions for all reference document intent skills in this directory. Each intent skill references this file for universal rules.

## Audience
AI agents helping developers test and debug FastEdge WASM applications using `@gcoredev/fastedge-test`.

## Output format

Structured Markdown with **no YAML frontmatter**. Concise, decision-dense — not a tutorial. Agents use this to generate correct test code, config files, and API calls.

## Cross-referencing rules

- **Never output file links or filenames** as cross-references (e.g. `[test-framework](test-framework.md)` or `./dotenv.md`). These reference documents live in different skill directories so relative links will not resolve.
- Instead, use **descriptive topic terms** that an agent can use to discover the relevant reference — e.g. "the test framework API reference", "the dotenv configuration guide", "the server API reference".
- In "See Also", "Next Steps", or "Related" sections, use plain-text topic descriptions with an em-dash explanation — e.g. `- Test framework API — defineTestSuite, runAndExit, and assertion helpers`.
- In "What to exclude" instructions within intent skills, filename references are acceptable since those are generator-facing scope boundaries, not output content.

## Code formatting rules

- **All code blocks must use fenced code blocks** with an appropriate language tag (e.g., ` ```ts `, ` ```json `, ` ```bash `). Never include raw unfenced code — it renders poorly and is inconsistent with other reference pages.
- **Inline code containing backticks** (e.g., template literals) must use double-backtick spans (``` `` `template ${expr}` `` ```) so the inner backticks render correctly.
- Source material sections that include file contents must wrap each file in its own fenced code block with the correct language tag.

## Accuracy constraints

- **No invented APIs**: Only document functions, methods, and properties that exist in the source. Do not infer or extrapolate APIs that are not declared.
- **Snippet validity**: Code snippets must use correct import paths and respect documented runtime constraints. Never write a snippet that contradicts a constraint stated in the same section.
- **Schema fidelity**: Config field names, types, defaults, and required status must exactly match the source schema. Do not add fields that do not exist in the schema.

## What to exclude

- Internal implementation details (Express middleware, React frontend, runner internals beyond what's documented)
- Installation prerequisites (Node version, etc.)
- Package history or changelog
- Marketing language or feature highlights
