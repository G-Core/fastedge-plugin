# Synthesis Instructions: examples-large-env-variable-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-large-env-variable-wasi-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::dictionary::get(name: &str) -> Option<String>` — import path `use fastedge::dictionary`, fallback with `unwrap_or_default()`
- Common patterns: call `dictionary::get("VAR_NAME")`, use `.len()` or process the returned string; handle absence gracefully with `unwrap_or_default()` or `unwrap_or_else(|| ...)`
- Gotchas: dictionary API is only for values that may exceed 64 KB — for normal-sized env vars `std::env::var()` is simpler and preferred; the `fastedge` crate must be declared as a dependency (not just `wstd`); returns `Option<String>` not `Result`, so no `?` propagation needed
- String literal accuracy: reproduce variable name strings exactly as they appear in the source (e.g. `"LARGE_CONFIG"`)
