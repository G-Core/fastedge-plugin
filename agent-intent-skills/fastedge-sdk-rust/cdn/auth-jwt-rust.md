# Synthesis Instructions: auth-jwt-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/auth-jwt-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [auth, jwt]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/jwt
```

## Example-specific extraction hints
- Extract JWT validation flow: header extraction, token parsing, signature verification, claim checking
- Show CDN-specific pattern: validate in `on_http_request_headers`, `send_http_response` to reject or `Action::Continue` to allow
- Include secret/key retrieval pattern for JWT verification
- "When to Use" hint: user wants to validate JWT tokens at the CDN layer before requests reach origin
