# Synthesis Instructions: examples-variables-and-secrets-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-variables-and-secrets-wasi-rust.md`

## Example-specific extraction hints
- API focus: `std::env::var("NAME") -> Result<String, VarError>` — use `.unwrap_or_default()` for safe fallback; `fastedge::secret::get("NAME") -> Result<Option<String>, ...>` — match `Ok(Some(v))` to extract, all other arms return empty string
- Common patterns: read env var with `env::var("USERNAME").unwrap_or_default()`; read secret with `match secret::get("PASSWORD") { Ok(Some(v)) => v, _ => String::new() }`; use both values in a formatted response body
- Gotchas: `secret::get` returns `Result<Option<String>>` not just `Option` — the outer `Result` must be handled before the inner `Option`; `fastedge` crate must be in Cargo.toml alongside `wstd`; env vars are plain-text and visible in app config — use secrets for sensitive values; `std::env` is available in WASI apps (unlike in some other WASM targets)
