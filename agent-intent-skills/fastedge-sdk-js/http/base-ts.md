# Synthesis Instructions: base-ts.md

> For shared cross-referencing rules and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/base-ts.md`

## Audience
AI agents scaffolding new FastEdge HTTP applications in TypeScript or JavaScript.

## Output goal
A base skeleton blueprint — the minimal, complete project structure an agent creates before layering any feature blueprints on top. Must contain every file needed for a working hello-world HTTP app.

## Output format

YAML frontmatter followed by structured Markdown sections. Follow the base skeleton format from `specs/002-scaffold-redesign/contracts/blueprint-format.md`.

### Frontmatter (required)
```yaml
---
type: base-skeleton
app_type: http
languages: [typescript, javascript]
template_origin: http-base
source_repo: <github-url>
source_ref: <commit-sha-or-tag>
updated: <YYYY-MM-DD>
---
```

### Required sections (in this order)

1. **Directory Structure** — tree of all files and directories in the project
2. **Files** — complete content of every file:
   - `package.json` — include all dependencies and scripts exactly as they appear
   - `src/index.js` (or `index.ts`) — the entry point
   - Any config files (tsconfig.json if TypeScript)
3. **Build Configuration** — the `fastedge-build` command and npm scripts

## Extraction rules
- Extract the **complete** file contents — do not summarize or abbreviate
- Include dependency versions exactly as declared in package.json
- The entry point pattern (`addEventListener("fetch", ...)` or equivalent) must be preserved exactly
- Do not add explanatory prose — this is a structural reference, not documentation
- A single TS-sourced blueprint covers both TypeScript and JavaScript output

## What to exclude
- README content
- Test files
- node_modules or build artifacts
- Explanations of what the code does
- "When to use" guidance (that belongs in feature blueprints)
