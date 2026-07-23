# Synthesis Instructions: api-key-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/api-key-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [auth, api-key]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/apiKey
```

## Example-specific extraction hints
- Extract `getSecret("API_KEY")` for the expected key — returns `string`, empty string when missing (not null) — and `stream_context.headers.request.get("X-API-Key")` for the provided key
- Show the three-branch validation: missing secret → 500 (misconfiguration), missing client header → 401 with `WWW-Authenticate: API-Key` header (use `makeHeaderPair`/`Array<HeaderPair>`), invalid key → 403
- Show `send_http_response(status, statusText, String.UTF8.encode(body), headers)` for blocking responses
- Show `stream_context.headers.request.remove("X-API-Key")` to strip the key before upstream forwarding — note this is the FastEdge CDN platform's empty-string-set behavior, not a true delete, so the upstream sees `X-API-Key:` (empty) rather than a missing header
- Import `getSecret` and `setLogLevel` from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`; `makeHeaderPair`, `HeaderPair`, `send_http_response` from `@gcoredev/proxy-wasm-sdk-as/assembly`
- All validation runs in `onRequestHeaders`; no new dependencies beyond the base skeleton
- "When to Use" hint: user wants to validate an X-API-Key request header against a stored secret at the CDN layer — a simpler alternative to JWT when expiry and claims are not required
