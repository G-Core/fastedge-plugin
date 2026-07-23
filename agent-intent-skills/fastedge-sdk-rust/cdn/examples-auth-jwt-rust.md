# Synthesis Instructions: examples-auth-jwt-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-auth-jwt-rust.md`

## Example-specific extraction hints
- API focus: Authorization header extraction via proxy-wasm, token parsing/verification (which crate, which functions), claim validation
- Common patterns: extract Bearer token, validate and check claims, return 401/403 for invalid
- Gotchas: key management (secrets vs env vars), algorithm constraints in WASM, clock skew, token size
