# Synthesis Instructions: body-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/body-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [body-manipulation]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/body
```

## Example-specific extraction hints
- Extract body buffering pattern: return `FilterDataStatusValues.StopIterationAndBuffer` until `end_of_stream`, then process
- Show `get_buffer_bytes` / `set_buffer_bytes` with `BufferTypeValues.HttpRequestBody` and `BufferTypeValues.HttpResponseBody`
- Show header manipulation for body changes (removing content-length, setting chunked transfer-encoding via `stream_context.headers`)
- Show cross-hook coordination between header and body hooks
- "When to Use" hint: user wants to inspect, modify, or redact request or response bodies at the CDN layer
