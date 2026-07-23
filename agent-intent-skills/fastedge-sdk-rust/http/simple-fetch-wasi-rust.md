# Synthesis Instructions: simple-fetch-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/simple-fetch-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [outbound-fetch, header-driven-routing]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/simple_fetch
```

## Example-specific extraction hints
- API focus: `wstd::http::Client::new()`, `.send(req).await`, `Request::get(url).header(k, v).body(Body::empty())`; reading target URL from an incoming request header (`x-fetch-url`)
- Show how to extract a header value from the incoming request: `request.headers().get("x-fetch-url").and_then(|v| v.to_str().ok()).unwrap_or(default)`
- The response from `client.send().await` is returned directly without decomposition — simpler than the pass-through pattern in outbound_fetch
- "When to Use" hint: user wants to make an outbound HTTP request to a URL specified by the incoming request (via a header) and return the upstream response directly
