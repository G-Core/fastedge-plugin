# Synthesis Instructions: geo-redirect-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/geo-redirect-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [geo-routing, geo-redirect]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/geo_redirect
```

## Example-specific extraction hints
- Extract country detection via `self.get_property(vec!["request.country"])` — returns `Option<Vec<u8>>`, decode with `.and_then(|b| String::from_utf8(b).ok()).unwrap_or_default()` for safe fallback
- Show env-var-based origin mapping: `DEFAULT` env var for fallback, country code as env var name for per-country origins (e.g., `US`, `DE`, `GB`)
- Show URL rewriting pattern: `self.set_property(vec!["request.url"], Some(url.as_bytes()))` to redirect to a different origin
- Show path preservation: read `request.path`, append to new origin URL
- Show `self.set_http_request_header("Host", Some(&host))` for Host header preservation
- CDN pattern: all routing logic in `on_http_request_headers`, no body hooks
- "When to Use" hint: user wants to route requests to different origins based on the client's geographic location
