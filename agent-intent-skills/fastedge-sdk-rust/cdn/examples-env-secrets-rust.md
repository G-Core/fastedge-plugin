# Synthesis Instructions: examples-env-secrets-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-env-secrets-rust.md`

## Example-specific extraction hints
- API focus: `std::env::var(name)` for environment variables, `fastedge::proxywasm::secret::get(name)` for secrets — returns `Result<Option<Vec<u8>>, u32>`
- Show when to use env vars vs secrets: non-sensitive configuration in env vars, sensitive values (passwords, API keys) in secrets
- Show `secret::get` return type handling: `.ok().flatten().and_then(|v| String::from_utf8(v).ok())` chain for converting `Result<Option<Vec<u8>>, u32>` to `Option<String>`
- Common patterns: read config in `on_http_request_headers`, forward as request headers to upstream
- Gotchas: env vars set at deployment time (not runtime-configurable), secrets are platform-managed with Vec<u8> return (must convert to String), `unwrap_or_default()` for graceful fallback
