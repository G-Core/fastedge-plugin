# Synthesis Instructions: examples-large-dictionary-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-large-dictionary-as.md`

## Example-specific extraction hints
- API focus: `getDictionary(name)` from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge` — returns `string`, empty for not-found
- Contrast with `getEnv`: dictionary supports values exceeding the 64KB WASI env-var limit; for normal-sized values prefer `getEnv` (lower overhead)
- Show usage inside `onRequestHeaders`: read once, forward size or summary as a header (the example sets `x-config-size`)
- Gotchas: empty-string (not null) check; values can be megabytes — do not log the full payload; AssemblyScript `string` is UTF-16, decoded on the SDK side; no try/catch — there is no error variant, just an empty result on miss
