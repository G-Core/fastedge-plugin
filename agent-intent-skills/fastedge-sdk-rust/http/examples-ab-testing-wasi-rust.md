# Synthesis Instructions: examples-ab-testing-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-ab-testing-wasi-rust.md`

## Example-specific extraction hints
- API focus: `wstd::http::Client::new().send(outbound_req).await`, `Request::get(&url).body(Body::empty())`, cookie header read via `req.headers().get("cookie")`, `Response::builder().header("set-cookie", ...)` — show return types and error propagation with `?`
- Common patterns: reading the `x-fastedge-abid` cookie and generating a new one when absent; stripping the internal cookie before forwarding to origin; appending `ab-test-<name>` request headers; returning the origin response with a long-lived `set-cookie`
- Gotchas: `generate_xid()` uses `SystemTime` subsecond nanos as weak entropy — document that this is intentionally simplistic and a `wasi-random`-backed RNG should replace it in production; the `is_valid_xid` check ensures the float is in `[0.0, 1.0)` before trusting a cookie value from the client; `env::var("OUTBOUND_URL")` must be non-empty or the handler returns 500 before doing any work
