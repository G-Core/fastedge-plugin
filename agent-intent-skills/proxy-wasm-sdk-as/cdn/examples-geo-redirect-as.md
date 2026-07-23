# Synthesis Instructions: examples-geo-redirect-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-geo-redirect-as.md`

## Example-specific extraction hints
- API focus: `get_property("request.country")` for geo data, header manipulation for routing
- Show country-based origin selection pattern (different upstream per country code)
- Show `stream_context.headers.request.replace` for modifying the Host or other routing headers
- Contrast with geoblock pattern: redirect routes to different origins, geoblock rejects entirely
- Gotchas: property returns ArrayBuffer that must be decoded, redirect happens by modifying request headers before origin fetch
