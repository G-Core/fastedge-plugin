# Synthesis Instructions: examples-env-secrets-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-env-secrets-as.md`

## Example-specific extraction hints
- API focus: `getEnv(name)` for environment variables, `getSecret(name)` and `getSecretEffectiveAt(name, slot)` for secrets
- Show when to use env vars vs secrets (non-sensitive config vs sensitive values)
- Both return `string` — not ArrayBuffer
- Import from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`
- Mark deprecated alternatives: `getEnvVar` → use `getEnv`, `getSecretVar` → use `getSecret`
- Gotchas: env vars are set at deployment time, secrets are platform-managed with rotation support via `getSecretEffectiveAt`
