# Synthesis Instructions: custom-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/custom-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [custom-response, path-routing, early-response]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/custom
```

## Example-specific extraction hints
- Extract path-based response dispatch: parse `request.path` property, split on `/` to extract path segments, use the first segment as a status code and optional second segment as a delay in milliseconds
- Show `self.send_http_response(code, vec![], None)` for short-circuit synthetic responses — returns `Action::Pause` to stop upstream processing; returning `Action::Continue` passes through to origin
- Show `std::thread::sleep(Duration::from_millis(delay))` for configurable artificial delay, parsed from the path segment
- Show error-handling pattern: validate path UTF-8 and numeric parse with early `send_http_response(400, ...)` + `Action::Pause` on failure
- Show `get_property(vec!["request.path"])` with safe UTF-8 decoding and leading `/` trim before splitting into segments
- "When to Use" hint: user wants to return custom HTTP responses (specific status codes, optional delays) directly from the CDN edge based on request path, without forwarding to origin — useful for testing, mocking, or health-check endpoints
