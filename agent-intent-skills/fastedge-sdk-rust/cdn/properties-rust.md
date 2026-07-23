# Synthesis Instructions: properties-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/properties-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [properties, geo, request-metadata]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/properties
```

## Example-specific extraction hints
- Extract all available request property paths: `request.url`, `request.host`, `request.path`, `request.scheme`, `request.extension`, `request.query`, `request.x_real_ip`, `request.country`, `request.city`, `request.asn`, `request.geo.lat`, `request.geo.long`, `request.region`, `request.continent`, `request.country.name`
- Show `self.get_property(vec!["request.country"])` returning `Option<Vec<u8>>` — must decode with `String::from_utf8_lossy()`
- Show `self.set_property(vec!["request.url"], Some(bytes))` for rewriting request URL/path/host
- Show `self.add_http_response_header_bytes()` for forwarding raw property bytes as headers
- CDN pattern: read and set properties in `on_http_request_headers`
- "When to Use" hint: user wants to read request metadata (URL, geo-IP, path, query) or rewrite request properties at the CDN layer
