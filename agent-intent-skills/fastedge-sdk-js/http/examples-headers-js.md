# Synthesis Instructions: examples-headers-js.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-headers-js.md`

## Example-specific extraction hints
- API focus: Headers API — `get`, `set`, `append`, `delete`, `has`, `entries` iteration
- Reading request headers (`request.headers.get()`), setting response headers
- Common patterns: echo request headers, add custom response headers, conditional logic on header values
- Gotchas: immutable vs mutable headers, case sensitivity, reserved headers
