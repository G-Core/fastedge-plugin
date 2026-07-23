# Synthesis Instructions: examples-kv-store-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-kv-store-wasi-rust.md`

## Example-specific extraction hints
- API focus: `key_value::Store::open(name)`, `get()`, `set()` — return types, `Result` handling
- Common patterns: basic open/get/set, error handling with `?`, using KV Store in the WASI handler
- Gotchas: ownership, lifetime considerations, error types, WASI-specific constraints
- String literal accuracy: when reproducing code snippets that contain error messages (e.g. `anyhow!("missing param '...'")`) copy the exact string from the source — do not substitute parameter names from adjacent lines or similar functions
