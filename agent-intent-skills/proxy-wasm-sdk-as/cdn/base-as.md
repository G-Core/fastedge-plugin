# Synthesis Instructions: base-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/base-as.md`

## Frontmatter
```yaml
---
type: base-skeleton
app_type: cdn
languages: [assemblyscript]
template_origin: cdn-base
source_example: proxy-wasm-sdk-as/examples/helloWorld
source_repo: <github-url>
source_ref: <commit-sha-or-tag>
updated: <YYYY-MM-DD>
---
```

## Example-specific extraction hints
- This is the **base skeleton** — the minimal starting point for all CDN AssemblyScript apps
- Extract the complete directory structure and all file contents (assembly/index.ts, package.json, asconfig.json, .gitignore)
- The helloWorld example is already minimal — extract it as-is without stripping
- Show all 4 lifecycle hooks with pass-through implementations (return Continue)
- package.json must use the published npm version (`@gcoredev/proxy-wasm-sdk-as: "^1.2.0"`) — NOT the `file:../..` dev reference
- Include build configuration section showing `asconfig.json` with `"use": "abort=abort_proc_exit"` requirement
- Include tsconfig.json extending assemblyscript std
