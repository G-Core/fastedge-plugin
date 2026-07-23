# Synthesis Instructions: md2html-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/md2html-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [response-body-transformation, content-type-rewriting, markdown-rendering]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/md2html
```

## Example-specific extraction hints
- Extract three-hook pipeline: `on_http_request_headers` rewrites the request path with an optional `BASE` env var prefix and strips `Accept-Encoding` to prevent gzip; `on_http_response_headers` checks `Content-Type` for `text/plain` or `text/markdown`, clears `Content-Length`, sets `Transfer-Encoding: Chunked`, rewrites `Content-Type` to `text/html`, and sets a `response.markdown` property as a processing flag; `on_http_response_body` reads the flag, buffers the full body, converts Markdown to HTML with `pulldown-cmark`, and writes the result back
- Show `Accept-Encoding` removal in request hook: `self.set_http_request_header("Accept-Encoding", None)` to prevent a gzip-compressed response body that can't be processed — note that on the FastEdge CDN platform this sets the header to empty string rather than removing it
- Show cross-hook signalling via `self.set_property(vec!["response.markdown"], Some(b"true"))` in response-headers hook; checked in body hook with `self.get_property(vec!["response.markdown"])` presence test
- Show `pulldown_cmark` usage: `Parser::new_ext(md, Options::ENABLE_TABLES | Options::ENABLE_FOOTNOTES)`, `push_html` into a `String`, wrapped with `<!DOCTYPE html><html><body>…</body></html>`
- Show path rewriting: read `request.path` property, prepend `BASE` env var (trimmed of trailing `/`), write back with `self.set_property(vec!["request.path"], Some(new_url.as_bytes()))`
- Show body buffering: return `Action::Pause` when `!end_of_stream`; retrieve with `self.get_http_response_body(0, body_size)` and write result with `self.set_http_response_body(0, body_size, body)`
- "When to Use" hint: user wants to serve Markdown files from origin as rendered HTML at the CDN edge, with optional base-path rewriting to locate the raw `.md` files
