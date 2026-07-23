# Synthesis Instructions: examples-hello-world-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-hello-world-wasi-rust.md`

## Example-specific extraction hints
- API focus: `#[wstd::http_server]` async handler macro, `wstd::http::{Request, Response}`, `wstd::http::body::Body`, `Response::builder().status().header().body()`
- Common patterns: async `main` receiving `Request<Body>`, return `anyhow::Result<Response<Body>>`, read `request.uri()` for the incoming URL, build response with `Body::from(string)`
- Distinguish from basic: this uses `wstd` types and `async fn` — contrast with `#[fastedge::http]` sync handler; note `wasm32-wasip2` build target required for async
- Gotchas: `?` operator on `Response::builder()...body(...)` returns `anyhow::Error`; `uri().to_string()` allocates — fine for responses but avoid in hot paths; `Body` is from `wstd::http::body`, not `fastedge::body`
