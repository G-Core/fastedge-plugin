# Synthesis Instructions: examples-http-call-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-http-call-rust.md`

## Example-specific extraction hints
- API focus: `self.dispatch_http_call(upstream, headers, body, trailers, timeout)` — returns `Result<u32, Status>` where `u32` is the token ID
- Show pseudo-header convention: headers vec must include `(":scheme", "https")`, `(":authority", "host")`, `(":path", "/path")` plus any custom headers
- Show async callback: implement `Context::on_http_call_response(token_id, num_headers, body_size, num_trailers)` — if `num_headers == 0`, the call failed
- Show response reading: `self.get_http_call_response_header(name)`, `self.get_http_call_response_headers()`, `self.get_http_call_response_body(0, body_size)`
- Show flow control: `self.resume_http_request()` to continue original request, `self.reset_http_request()` on failure
- Common patterns: `Action::Pause` in request hook → dispatch → callback fires → resume or reset
- Show `Status` enum mapping to HTTP status codes for error responses
- Gotchas: `Duration::from_millis()` for timeout, state tracking via struct fields across hooks, callback may fire before or after response hooks depending on timing
