# Synthesis Instructions: examples-outbound-fetch-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-outbound-fetch-basic-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::send_request(req) -> Result<Response<Body>, fastedge::Error>`, `Request::builder().uri().body(Body::empty())`, `serde_json::from_slice(&bytes) -> serde_json::Value`, `json!({...})` macro for constructing JSON response
- Common patterns: fire a single outbound GET to `jsonplaceholder.typicode.com/users`, read body bytes with `.body().to_vec()`, parse as JSON array, slice first 5 elements with `.iter().take(5)`, return shaped JSON object with `content-type: application/json`
- Show JSON shaping: `users.as_array()` → `Value::Array(arr.iter().take(5).cloned().collect())`; wrap in `json!({...})` with pagination fields; serialize with `.to_string()`
- Gotchas: `fastedge::send_request` error is converted with `.map_err(Error::msg)` (using `anyhow::Error`); `response.body().to_vec()` reads entire upstream response into memory — not suitable for large payloads; upstream URL is hardcoded; no error handling for non-200 upstream responses in this minimal example
