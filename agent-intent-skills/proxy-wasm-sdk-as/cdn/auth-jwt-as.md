# Synthesis Instructions: auth-jwt-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/auth-jwt-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [auth, jwt]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/jwt
```

## Example-specific extraction hints
- Extract `getSecret` usage for reading JWT signing keys
- Show external dependency: `@gcoredev/as-jwt` — this is a NEW dependency beyond the base skeleton
- Show JWT validation flow: extract Bearer token from Authorization header, validate, block with 401/403
- Show `send_http_response` for returning auth error responses
- Import `getSecret` from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`
- "When to Use" hint: user wants to validate JWT Bearer tokens and enforce authentication at the CDN layer
