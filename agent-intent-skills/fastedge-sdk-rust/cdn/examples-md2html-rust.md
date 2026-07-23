# Synthesis Instructions: examples-md2html-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-md2html-rust.md`

## Example-specific extraction hints
- API focus: `self.get_http_response_header("Content-Type")` to detect Markdown responses; `self.set_property(vec!["response.markdown"], Some(b"true"))` as a processing flag; `self.get_http_response_body(0, body_size)` to retrieve buffered body bytes; `self.set_http_response_body(0, body_size, body)` to replace with HTML; `self.set_property(vec!["request.path"], Some(bytes))` for path rewriting
- Show content-type detection: check `content_type.starts_with("text/plain")` or `starts_with("text/markdown")` — both trigger Markdown conversion
- Show body replacement pipeline: buffer with `Action::Pause` until `end_of_stream`; decode bytes with `String::from_utf8`; parse with `pulldown_cmark::Parser::new_ext`; push HTML into a `String`; write back with `set_http_response_body`
- Show `Accept-Encoding` suppression in request hook: set to `None` to avoid receiving a compressed body — on the FastEdge CDN platform this sets the header value to an empty string rather than removing it; origin must honour an empty `Accept-Encoding` as "no encoding preferred"
- Common patterns: `Content-Length: None` + `Transfer-Encoding: Chunked` before body replacement; `BASE` env var for path prefix with `.trim_end_matches('/')` normalization; `get_property`/`set_property` for cross-hook state
- Gotchas: skipping `Accept-Encoding` suppression causes origin to return gzip, making `String::from_utf8` fail silently and passing through raw bytes as HTML; `String::from_utf8(body_bytes)` returns `Result` — the example silently passes through on error rather than sending a 500, which is appropriate for a best-effort transform; `pulldown-cmark` parses CommonMark — GFM extensions (tables, footnotes) must be explicitly enabled via `Options` flags
