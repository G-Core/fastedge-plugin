# Synthesis Instructions: examples-custom-error-pages-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-custom-error-pages-rust.md`

## Example-specific extraction hints
- API focus: `self.get_property(vec!["response.status"])` for status detection (2-byte big-endian u16), `self.set_http_response_header()` for header manipulation, `self.set_http_response_body(0, body_size, bytes)` for body replacement, `include_str!` for compile-time template embedding
- Show response status decoding: `u16::from_be_bytes([bytes[0], bytes[1]])` — critical that `response.status` is NOT a string
- Show header preparation: remove `Content-Length`, set `Transfer-Encoding: Chunked`, set `Content-Type: text/html` for error status codes (400-599)
- Show body replacement: buffer in `on_http_response_body` until `end_of_stream`, then replace entire body
- Common patterns: detect error status in response headers → prepare for body replacement → render template in response body hook
- Show `handlebars::Handlebars` template engine with `serde_json::json!` data for dynamic content
- Gotchas: `response.status` is 2-byte binary (not a string), must check `bytes.len() == 2` before decoding, body replacement requires removing `Content-Length` first, `include_str!` embeds templates at compile time (not runtime file reads), `include!` with `OUT_DIR` for build-generated content
