# Synthesis Instructions: examples-markdown-render-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-markdown-render-basic-rust.md`

## Example-specific extraction hints
- API focus: `pulldown_cmark::{Options, Parser}`, `Parser::new_ext(md, Options::ENABLE_TABLES | Options::ENABLE_FOOTNOTES)`, `pulldown_cmark::html::push_html(&mut html, parser)`, `fastedge::send_request` for fetching Markdown from origin
- Common patterns: fetch raw Markdown from `BASE + path` → parse with pulldown-cmark → render to HTML string → wrap in `<!DOCTYPE html><html><body>...</body></html>`; optional `HEAD` env var for injecting `<head>` content (e.g., CSS links); `mime::TEXT_HTML` for `Content-Type`
- Show env var config: `BASE` (required, origin server URL prefix), `HEAD` (optional, raw HTML injected into `<head>`)
- Gotchas: path must be non-empty and not `/` — return `400 BAD_REQUEST` otherwise; `base.trim_end_matches('/')` avoids double-slash when concatenating with path; redirect handling in `request_inner` follows up to 5 hops; `String::from_utf8(rsp.body().to_vec())` can fail if origin returns binary — return `500`
