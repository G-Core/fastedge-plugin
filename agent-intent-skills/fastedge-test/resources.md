# Synthesis Instructions: resources.md

> For shared cross-referencing rules, accuracy constraints, and exclusions see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/test/reference/resources.md`

## Audience
AI agents helping developers run one request through several CDN apps (a CDN resource) locally, in the debugger or in tests.

## Source file
`docs/RESOURCES.md`

## Output goal
The reference for multi-app resources: the resource file, how hooks, rules and origins map to apps, and how a resource behaves in the debugger, in tests and on the edge. Follow the source's section order.

## Required sections (in this order)

1. **Overview** — one request through several apps: a CDN app per hook, the origin (a URL, the built-in origin, or an HTTP app of the resource); what passes between hooks; shared stores
2. **The Resource File** — every field, with a complete example
3. **Hooks** — which app runs each hook; `interruptOnError` and what the client gets when a hook's app fails
4. **Rules** — how a rule matches the request path and what it sets
5. **Origins** — URL, echo (`"built-in"`), declared built-in origin, HTTP app origin
6. **Request Context** — client and edge for a resource request
7. **Errors and Rebuilds** — load errors and what happens when an app is rebuilt
8. **In the Debugger** — the multi-app view and its result strip
9. **In Tests** — `createResource(fileOrObject, options?)` signature and options, the resource test suite type, one example
10. **On the Edge** — how the resource file maps to a real CDN resource

## What to exclude
- The single-app config file schema (belongs in test-config.md); link to it for `builtIn` origin fields
- Low-level runner internals (belongs in runner-internals.md)
- Stores details beyond what a resource shares (belongs in stores.md)

## Quality bar
The existing file at `plugins/gcore-fastedge/skills/test/reference/resources.md` sets the quality bar. Keep every field, error and edge mapping the source documents.
Keep the existing headings (`### Example Resource File`, `### URL Origin`, ``### Echo Origin (`"built-in"`)``, ...) unless the source removes the section; do not reword sentences that are still accurate.
