# Synthesis Instructions: env-secrets-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/env-secrets-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [env-vars, secrets, config]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/variablesAndSecrets
```

## Example-specific extraction hints
- Extract `getEnv(name)` for non-sensitive configuration and `getSecret(name)` for platform-managed secret values — both return `string` (empty string for not-found, never `null`)
- Show the empty-string check pattern (`value.length === 0` or `value === ""`) — do NOT show `value == null` because the SDK never returns null here
- Mention `getSecretEffectiveAt(name, slot)` as the rotation-aware variant
- Show forwarding values as request headers (`stream_context.headers.request.add(...)`) — but warn against logging full secret values (the example logs only the secret length)
- Import `getEnv`, `getSecret`, `setLogLevel` from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`
- No new dependencies beyond the base skeleton
- "When to Use" hint: user wants to read environment variables and platform-managed secrets at the CDN layer for configuration and credentials
