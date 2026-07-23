# Synthesis Instructions: examples-hello-world-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-hello-world-basic-rust.md`

## Example-specific extraction hints
- API focus: `#[fastedge::http]` sync handler macro, `fastedge::http::{Request, Response, StatusCode}`, `fastedge::body::Body`, `StatusCode::OK`, `Response::builder().status().header().body()`
- Common patterns: sync `fn main(req: Request<Body>) -> Result<Response<Body>>`, read `req.uri().to_string()`, build text response with `Body::from(format!(...))`, propagate builder error with `.map_err(Into::into)`
- Distinguish from WASI: this is the legacy sync handler (`#[fastedge::http]`); uses `fastedge::*` types rather than `wstd::*`; targets `wasm32-wasip1`
- Gotchas: `.map_err(Into::into)` is idiomatic here because `http::Error` converts into `anyhow::Error`; `StatusCode::OK` from `fastedge::http` is a re-export of `http::StatusCode`
