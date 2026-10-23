# Synthesis Instructions: component-imports-js.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/component-imports-js.md`

## Audience
AI agents helping developers call Wasm components (code written in Rust, Go, C/C++, Python, ...) from a FastEdge JavaScript/TypeScript app.

## Output goal
A reference agents use to decide whether a component is the right tool, configure the build, call the component correctly from JS/TS, and explain build errors. Source: `docs/COMPONENT_IMPORTS.md`.

## Required sections (in this order)

1. **When to use a component** — a library or existing code in another language, or a hot path that needs native speed. For what JS already does well, plain JS is simpler. State that component imports need `@gcoredev/fastedge-sdk-js` 2.7.0 or later.

2. **Build configuration** — the `components` field (`Record<string, string>`, WIT interface name → component file) and the repeatable `--component <interface>=<path>` flag, with one example of each. Several interfaces may come from one file; one build may use several files.

3. **Generated declarations** — `fastedge-components.d.ts` is written next to the entry file on every build with components, the app is type-checked against it, and it is the authoritative description of a component's types.

4. **WIT to JS types** — reproduce the source's WIT-to-JS table exactly. Do not add types it does not list.

5. **Calling and errors** — imports by interface name; calls are synchronous; data is copied in and out on every call. A WIT `result` error is thrown with the value in `error.payload`; show the try/catch.

6. **Resources** — a WIT `resource` becomes a class; keep the source's example.

7. **What a component may import** — only `wasi:*@0.2.x` and `gcore:*`; outgoing HTTP from a component goes through FastEdge like `fetch()` and follows the same rules.

8. **Limits** — every request runs a fresh instance, so component work counts against each request's time and memory budget; keep the source's measured table and the "check sizes before expensive work" advice.

9. **Build errors** — table of error message → cause, copied from the source.

10. **Known limitations** — as listed in the source.

## What to exclude
- How to write the component itself beyond one sentence (language toolchains are out of scope); the example pattern reference covers the Rust example
- Internal pipeline details (splicing, Wizer, composition tools)

## Quality bar
Error messages and the type table must match the source verbatim. Do not claim WASI interfaces beyond those the source says work.
