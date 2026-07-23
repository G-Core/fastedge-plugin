# Synthesis Instructions: examples-geoblock-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-geoblock-rust.md`

## Example-specific extraction hints
- API focus: client country detection via proxy-wasm properties/headers, allow/deny list logic
- Common patterns: read country from request properties, check against list, return 403 for blocked
- Gotchas: property availability timing, config approaches (env vars vs hardcoded), detection accuracy
