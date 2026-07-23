# Synthesis Instructions: body-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/body-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [body-manipulation]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/body
```

## Example-specific extraction hints
- Extract body buffering pattern: return `Action::Pause` until `end_of_stream`, then process
- Show `get_http_request_body` / `set_http_request_body` and response equivalents
- Show header manipulation for body changes (removing content-length, setting chunked transfer-encoding)
- Show cross-hook state via `set_property` / `get_property`
- "When to Use" hint: user wants to inspect, modify, or redact request or response bodies at the CDN layer
