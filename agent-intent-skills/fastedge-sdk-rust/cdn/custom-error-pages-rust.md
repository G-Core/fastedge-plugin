# Synthesis Instructions: custom-error-pages-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/custom-error-pages-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [error-pages, response-body]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/custom_error_pages
```

## Example-specific extraction hints
- Extract response status detection: `self.get_property(vec!["response.status"])` returns 2-byte big-endian `u16` — decode with `u16::from_be_bytes([bytes[0], bytes[1]])`
- Show header preparation in `on_http_response_headers`: remove `Content-Length`, set `Transfer-Encoding: Chunked`, set `Content-Type: text/html` for error responses (400-599)
- Show body replacement in `on_http_response_body`: buffer until `end_of_stream`, then replace body with `self.set_http_response_body(0, body_size, new_body)`
- Show `include_str!` macro for embedding HTML templates and CSS at compile time
- Show `handlebars::Handlebars` template rendering with `serde_json::json!` data
- Show `include!` with `concat!(env!("OUT_DIR"), ...)` for build-generated maps (image_map, message_map)
- Show status code fallback logic: exact match first, then 4xx→4000 / 5xx→5000 generic fallback
- CDN pattern: uses `on_http_response_headers` (detect error, prepare headers) and `on_http_response_body` (replace body with branded HTML)
- "When to Use" hint: user wants to replace default 4xx/5xx error responses with custom branded HTML error pages at the CDN layer
