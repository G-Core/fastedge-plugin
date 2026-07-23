# Synthesis Instructions: examples-fetch-js.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-fetch-js.md`

## Example-specific extraction hints
- API focus: `fetch(url, options)` — supported options, response handling (status, headers, body)
- Note any differences from standard browser/Node fetch API
- Common patterns: simple GET, POST with JSON body, error handling
- Gotchas: runtime constraints on outbound requests, DNS resolution, connection limits
