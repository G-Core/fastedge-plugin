# Synthesis Instructions: examples-properties-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-properties-as.md`

## Example-specific extraction hints
- API focus: `get_property(path)` — catalog all available request property paths
- Document each property: `request.path`, `request.query`, `request.country`, `response.status`
- Show ArrayBuffer decoding patterns for each (most are UTF-8 strings, `response.status` is 2-byte big-endian u16)
- Show which properties are available in which lifecycle phase (request vs response)
- Gotchas: `response.status` is NOT a string — it's a 2-byte binary value, `get_property` returns `ArrayBuffer | null`
