# Shared Reference Document Instructions

This file contains shared instructions for all `fastedge-templates` reference document intent
skills in this directory. Each intent skill references this file for universal rules.

## Audience

AI agents helping a developer decide whether to hand-build something FastEdge already ships as
a template, and — separately — agents helping a developer who has already deployed a template
wire it into their own origin codebase.

## Output format

Structured Markdown with **no YAML frontmatter**. Concise, decision-dense — not a tutorial.

## Cross-referencing rules

- **Never output file links or filenames** as cross-references. These reference documents live
  in different skill directories so relative links will not resolve.
- Use **descriptive topic terms** an agent can use to discover the relevant reference — e.g.
  "the edge-sso integration reference", not `edge-sso-integration.md`.

## Code formatting rules

- All code blocks use fenced code blocks with a language tag.
- Inline code containing backticks uses double-backtick spans.

## General extraction rules

- Every template is a standalone, already-built app deployed via the Gcore portal template
  gallery — **not** something the plugin's `/scaffold` or `/deploy` skills build or ship. Never
  imply a template is scaffolded from `create-fastedge-app` or built via `/gcore-fastedge:deploy`.
- Preserve exact route paths, JSON field names, and env var names verbatim from source — these
  are contracts a customer's origin code depends on; a typo here breaks a real integration.
- Preserve security-load-bearing statements verbatim (e.g. redirect validation, origin-lock
  requirements) — do not summarize away a "must" into a "should".

## What to exclude

- Template internal implementation details (how the wasm binary is built)
- Deployment/CI details (Harbor, Rust build toolchain, GitHub Actions) — irrelevant to a
  customer who deploys via the portal
- Marketing language
