# Synthesis Instructions: examples-outbound-fetch-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-outbound-fetch-wasi-rust.md`

## Example-specific extraction hints
- API focus: `wstd::http::Client` — `Client::new()`, `.send(req).await` returns `Result<Response<Body>, ...>`; `Request::get(url)` builder, `.body(Body::empty())`, `.map_err(|e| anyhow!(...))` for error mapping
- Common patterns: build request with `Request::get`, send with `Client::new().send().await`, use `into_parts()` to destructure and reconstruct response preserving upstream status and headers
- Gotchas: not calling `.contents()` on the body is intentional and enables streaming — materializing the body with `.contents()` would buffer everything in memory; `wstd::http::Client` is only available in WASI async apps; `anyhow` is needed for error mapping
