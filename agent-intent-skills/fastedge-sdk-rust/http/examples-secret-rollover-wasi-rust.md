# Synthesis Instructions: examples-secret-rollover-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-secret-rollover-wasi-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::secret::get(name: &str) -> Result<Option<String>, ...>` returns the latest slot value; `fastedge::secret::get_effective_at(name: &str, slot: u32) -> Result<Option<String>, ...>` uses greatest-matching-slot semantics; both return `Result`, propagate with `map_err(|e| anyhow!(...))?`
- Common patterns: read slot from request header with `headers().get("x-slot")`, parse to `u32`, default to current unix timestamp; call both `secret::get` and `secret::get_effective_at` to compare current vs. historically-effective value
- Gotchas: slot lookup uses greatest-matching rule — the slot with the highest value that is <= `effective_at` is returned, not an exact match; `slot` is `u32` so timestamps after year 2106 overflow; both functions return `Result<Option<String>>` — `None` means the secret exists but has no matching slot, not that the secret is absent; `fastedge` crate must be in dependencies alongside `wstd`
