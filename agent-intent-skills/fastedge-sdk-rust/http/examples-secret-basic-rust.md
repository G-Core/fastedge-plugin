# Synthesis Instructions: examples-secret-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-secret-basic-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::secret::get(name) -> Result<Option<Vec<u8>>, secret::Error>`, `fastedge::secret::get_effective_at(name, timestamp_u32) -> Result<Option<Vec<u8>>, secret::Error>`, `secret::Error` variants: `AccessDenied`, `DecryptError`, `Other(String)`
- Common patterns: call `secret::get("SECRET")` → match on `Ok(Some(value))`, `Ok(None)`, and each `Err` variant separately; call `secret::get_effective_at("SECRET", ts as u32)` with current Unix timestamp from `SystemTime::now().duration_since(UNIX_EPOCH).as_secs()`; return both values in response body for comparison
- Show error mapping: `AccessDenied` → 403 empty; `Other(msg)` → 403 with message body; `DecryptError` → 500 empty; `Ok(None)` → 404 empty
- Gotchas: `get` returns `Option` — a secret can exist but have no value; `get_effective_at` retrieves the secret version active at a given Unix timestamp (useful for scheduled rotations); timestamp is `u32`, not `u64` — cast `as u32`; `secret::Error` is its own type, not `anyhow::Error`; use `.map_err(Error::msg)` to convert for the `?` operator on `Response::builder()`
