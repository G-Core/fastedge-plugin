# Synthesis Instructions: examples-api-key-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-api-key-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::proxywasm::secret::get("API_KEY")` returning `Result<Option<Vec<u8>>, u32>`, `self.get_http_request_header("X-API-Key")` for extracting the provided key, `self.send_http_response()` for auth error responses, `self.set_http_request_header("X-API-Key", None)` for stripping the key before forwarding
- Show validation flow: read expected key from secret → extract provided key from header → compare → respond with 401 (missing), 403 (invalid), or continue
- Common patterns: secret retrieval with `Result<Option<Vec<u8>>, u32>` chaining, header-based auth validation, header stripping before upstream forwarding
- Show `WWW-Authenticate: API-Key` response header for 401 responses
- Gotchas: `secret::get` returns `Vec<u8>` (convert with `.and_then(|v| String::from_utf8(v).ok())` to avoid panics on invalid UTF-8), empty key should be treated as missing, stripping the API key before forwarding prevents credential leakage to upstream, simpler than JWT when token expiry and claims are not needed
