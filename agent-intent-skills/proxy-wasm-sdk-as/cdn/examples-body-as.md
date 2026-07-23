# Synthesis Instructions: examples-body-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-body-as.md`

## Example-specific extraction hints
- API focus: `onRequestBody`/`onResponseBody` buffering pattern with `FilterDataStatusValues.StopIterationAndBuffer`
- Show `get_buffer_bytes` / `set_buffer_bytes` with appropriate `BufferTypeValues`
- Show coordination between header hooks and body hooks (content-length removal, transfer-encoding)
- Gotchas: body size limits, buffering memory, streaming vs buffered, content-type awareness
- Note that body hooks only fire if request/response has a body
