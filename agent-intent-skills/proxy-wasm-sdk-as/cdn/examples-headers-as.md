# Synthesis Instructions: examples-headers-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-headers-as.md`

## Example-specific extraction hints
- API focus: `stream_context.headers.request` and `stream_context.headers.response` — all methods (get, add, replace, remove, get_headers, set_headers)
- Show request-phase vs response-phase manipulation
- Show header iteration pattern using `get_headers()` returning `HeaderPair[]`
- Show `String.UTF8.decode` for reading header key/value from ArrayBuffer
- Gotchas: response headers not available during request phase (causes panic), `remove` behavior (FastEdge platform limitation: sets the value to an empty string rather than truly removing the header — when checking for absence, test for both missing and empty string)
