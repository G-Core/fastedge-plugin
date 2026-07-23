# Synthesis Instructions: examples-body-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-body-rust.md`

## Example-specific extraction hints
- API focus: `on_http_request_body`/`on_http_response_body` buffering pattern, `get_http_request_body`/`set_http_request_body` and response equivalents
- Show coordination between header hooks and body hooks (content-length removal, chunked transfer-encoding)
- Cross-hook state via `set_property`/`get_property`
- Gotchas: body size limits, buffering memory, streaming vs buffered, content-type awareness
