# Synthesis Instructions: examples-simple-fetch-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-simple-fetch-wasi-rust.md`

## Example-specific extraction hints
- API focus: `wstd::http::Client::new()`, `.send(req).await -> Result<Response<Body>, ...>`; `Request::get(url).header(k, v).body(Body::empty())` builder; extracting header values from the incoming `Request<Body>` with `.headers().get(name).and_then(|v| v.to_str().ok()).unwrap_or(default)`
- Common patterns: read target URL from an incoming header with a fallback default; build outbound request with a custom header; send with `Client::new().send().await`; return the response object directly (no decomposition needed)
- Gotchas: `println!` is the correct logging mechanism (not `eprintln!`); the URL must be a fully-qualified string — convert with `.to_string()` before use in `Request::get`; header value parsing chain (`.get` -> `.to_str()` -> `.parse()`) returns `Option`, use `unwrap_or` for safe fallback; `anyhow` needed for `anyhow!()` macro in error mapping
