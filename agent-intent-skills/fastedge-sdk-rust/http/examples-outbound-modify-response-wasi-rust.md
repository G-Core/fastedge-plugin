# Synthesis Instructions: examples-outbound-modify-response-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-outbound-modify-response-wasi-rust.md`

## Example-specific extraction hints
- API focus: `body.contents().await?` returns `&[u8]`; `serde_json::from_slice::<Value>(&bytes)?`; `serde_json::json!` macro for constructing output; `Value::as_array()` for array access; `.take(n)` to slice
- Common patterns: fetch with `Client::new().send().await`, destructure with `into_parts()`, await body bytes, parse and reshape JSON, build new `Response` with explicit `content-type: application/json` header
- Gotchas: `body.contents().await?` buffers the entire upstream body in WASM memory — unsuitable for very large payloads; `serde_json` must be added to Cargo.toml; `into_parts()` consumes the response so headers cannot be accessed after this call; `Value::as_array()` returns `Option<&Vec<Value>>`, handle `None` case
