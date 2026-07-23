# Synthesis Instructions: examples-geoblock-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-geoblock-as.md`

## Example-specific extraction hints
- API focus: `getEnv` for configuration, `get_property("request.country")` for geo data, `send_http_response` for blocking
- Show property path format and ArrayBuffer decoding for country code
- Show blocklist parsing pattern (comma-separated string from env var)
- Gotchas: property returns `ArrayBuffer | null` — must decode to string, country code format (2-letter ISO)
