# Synthesis Instructions: examples-static-assets-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-static-assets-wasi-rust.md`

## Example-specific extraction hints
- API focus: `include_str!("../assets/file")` embeds a UTF-8 text file as `&'static str` at compile time; `include_bytes!("../assets/file")` for binary assets; `req.uri().path()` returns the request path as `&str`; `wstd::http::StatusCode` for `StatusCode::OK` / `StatusCode::NOT_FOUND`
- Common patterns: define a struct holding `content_type` and `body` as `&'static str`; declare static asset constants using `include_str!`; implement a `lookup(path) -> Option<&'static Asset>` match expression; return 404 with plain-text body for unmatched paths
- Gotchas: the WASM runtime has no file system — all assets must be embedded at compile time with `include_str!`/`include_bytes!`; `include_str!` path is relative to the source file, not the crate root; binary assets need `include_bytes!` and the body should be wrapped appropriately (e.g. `bytes::Bytes::from_static`); large embedded assets increase binary size and therefore cold-start time
