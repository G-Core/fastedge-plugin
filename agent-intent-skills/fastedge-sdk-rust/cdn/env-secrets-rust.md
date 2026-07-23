# Synthesis Instructions: env-secrets-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/env-secrets-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [env-vars, secrets]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/variables_and_secrets
```

## Example-specific extraction hints
- Extract `std::env::var()` usage for reading environment variables in CDN context
- Extract `fastedge::proxywasm::secret::get()` usage — returns `Result<Option<Vec<u8>>, u32>`, convert bytes with `.ok().flatten().and_then(|v| String::from_utf8(v).ok())` for safe fallback
- Show the pattern of reading config in `on_http_request_headers` and forwarding as request headers via `self.add_http_request_header()`
- Show `unwrap_or_default()` / `.ok().flatten().and_then(...)` chaining for graceful fallback
- CDN pattern: all reads happen in `on_http_request_headers`; no body hooks needed
- "When to Use" hint: user wants to read environment variables and secrets in a CDN app to configure behavior or forward credentials to upstream
