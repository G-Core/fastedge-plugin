# Shared Scaffold Blueprint Instructions

This file contains shared instructions for all feature blueprint intent skills in this directory. Each per-example intent skill references this file and adds only its example-specific details.

## Audience
AI agents scaffolding new FastEdge applications. Blueprints are consumed by the scaffold skill to assemble tailored projects.

## Output format

YAML frontmatter followed by structured Markdown sections. Follow the **feature blueprint** format from `specs/002-scaffold-redesign/contracts/blueprint-format.md`.

### Required sections (in this order)

1. **When to Use** — 1-2 sentences describing when this blueprint should be selected. The agent uses this for matching against user intent.
2. **Dependencies to Add** — package names and versions to merge into the base skeleton's package.json. JSON object format.
3. **Files to Create** — complete content of any new files this feature adds.
4. **Files to Modify** — for each existing base skeleton file that needs changes:
   - Import statements to add
   - Code to insert into the handler/entry point, with comments indicating placement
5. **Build Notes** — any special build steps, config changes, or caveats (e.g., `.fastedge/build-config.js`)

### Frontmatter fields (required)

```yaml
---
type: feature
app_type: http | cdn
languages: [typescript, javascript] | [rust]
capabilities: [<capability-tags>]
base_skeleton: http-base | cdn-base
source_example: <repo>/<path>
source_repo: <github-url>
source_ref: <commit-sha-or-tag>
updated: <YYYY-MM-DD>
---
```

## Code formatting rules

- **All code blocks must use fenced code blocks** with an appropriate language tag (e.g., ` ```ts `, ` ```json `, ` ```bash `). Never include raw unfenced code — it renders poorly and is inconsistent with other reference pages.
- **Inline code containing backticks** (e.g., template literals) must use double-backtick spans (``` `` `template ${expr}` `` ```) so the inner backticks render correctly.
- In "Files to Create" and "Source Material" sections, wrap each file's contents in its own fenced code block with the correct language tag.

## General extraction rules

- Extract **complete** file contents for new files — do not summarize or abbreviate
- Show modifications **relative to the base skeleton** — what to add/change, not the full file
- Preserve exact API signatures, import paths, and type annotations
- Include dependency versions exactly as declared in package.json
- If a `.fastedge/build-config.js` or other config file exists, include it in Build Notes
- Content must be useful to **any AI coding tool**, not just Claude Code (MCP constraint R-007)

## Cross-referencing rules

- **Never output file links or filenames** as cross-references (e.g. `[BUILD_CLI](BUILD_CLI.md)` or `./static-sites.md`). These reference documents live in different skill directories so relative links will not resolve.
- Instead, use **descriptive topic terms** that an agent can use to discover the relevant reference — e.g. "the build CLI reference", "the static sites guide".

## What to exclude

- The base skeleton files themselves (those come from the base skeleton blueprint)
- README content
- Test files
- node_modules or build artifacts
- Conceptual explanations or "when to use" prose beyond the matching criteria (that belongs in the docs pattern file)
