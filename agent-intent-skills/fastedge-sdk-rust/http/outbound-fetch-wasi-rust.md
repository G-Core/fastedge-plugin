# Synthesis Instructions: outbound-fetch-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/outbound-fetch-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [outbound-fetch]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/outbound_fetch
```

## Example-specific extraction hints
- API focus: `wstd::http::Client::new()`, `Client::send(req).await`, `Request::get(url).body(Body::empty())`
- Show the pass-through pattern: `upstream_resp.into_parts()` to split status/headers/body, then reconstruct a new `Response` with those parts
- The body is not materialized (`.contents()` not called) so it streams through to the client as upstream produces it — call this out explicitly
- "When to Use" hint: user wants to proxy an upstream HTTP request and return the response verbatim (status, headers, and body unchanged) without reading or transforming the body
