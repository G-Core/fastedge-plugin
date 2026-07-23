# Synthesis Instructions: examples-geo-redirect-js.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-geo-redirect-js.md`

## Example-specific extraction hints
- API focus: client location detection (headers, ClientInfo), env vars for country-to-URL mappings, redirect response construction
- Common patterns: basic geo-redirect by country code, configurable mappings via env vars, fallback for unknown locations
- Gotchas: geolocation accuracy, header availability, caching with Vary
