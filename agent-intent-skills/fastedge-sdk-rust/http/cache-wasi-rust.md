# Synthesis Instructions: cache-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/cache-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [cache, outbound-http]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/cache
```

## Example-specific extraction hints
- API focus: `fastedge::cache::get(&key)` returns `Result<Option<Vec<u8>>>`, `fastedge::cache::set(&key, &bytes, Some(ttl_ms))` — synchronous calls despite the async WASI handler
- Show the cache-key construction pattern: `format!("cache:{path_and_query}")` using `req.uri().path_and_query()`
- Show the cache hit fast-path (return immediately with `x-cache: hit` header) vs miss path (forward to origin, store on 2xx, replay with `x-cache: miss`)
- Show `body.contents().await?.to_vec()` for reading the upstream response body before caching
- New dependencies vs base skeleton: `fastedge = "0.4"` (note: source uses a path dep, emit the crates.io version)
- "When to Use" hint: user wants to cache upstream responses at the edge by request path, with a configurable TTL, to reduce origin load
