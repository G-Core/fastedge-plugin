# Synthesis Instructions: examples-auth-jwt-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-auth-jwt-as.md`

## Example-specific extraction hints
- API focus: `getSecret` for reading JWT keys, `@gcoredev/as-jwt` for validation
- Show Bearer token extraction from Authorization header
- Show JWT validation flow and error response pattern (401/403)
- Show `getSecretEffectiveAt` for secret rotation scenarios
- Gotchas: secret returns string (not ArrayBuffer), JWT library is a separate dependency, validation happens in `onRequestHeaders`
