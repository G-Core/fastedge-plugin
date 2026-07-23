# Synthesis Instructions: outbound-modify-response-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/outbound-modify-response-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [outbound-fetch, json-transform]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/outbound_modify_response
```

## Example-specific extraction hints
- API focus: `body.contents().await?` to materialize the upstream body as bytes, `serde_json::from_slice` to parse, `serde_json::json!` macro to construct the response payload
- Show the full transform pipeline: fetch → `into_parts()` → `body.contents().await?` → parse JSON → reshape → serialize → return new `Response` with `content-type: application/json`
- `serde_json` must be added to dependencies (not in base skeleton)
- "When to Use" hint: user wants to fetch JSON from an upstream service, reshape or filter the data, and return a new JSON response with a custom structure
