# Synthesis Instructions: examples-cache-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-cache-basic-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::cache::get(&key) -> anyhow::Result<Option<Vec<u8>>>`, `fastedge::cache::set(&key, bytes, Some(ttl_ms)) -> anyhow::Result<()>`, cache key string format `"page:{path}"`
- Common patterns: cache-aside loop — `cache::get` → hit returns cached bytes; miss generates body, calls `cache::set`, then returns; `x-cache: hit` / `x-cache: miss` response headers for observability
- Show env var: `CACHE_TTL_MS` parsed as `u64` with `env::var().ok().and_then(|v| v.parse().ok()).unwrap_or(30_000)` default
- Gotchas: `cache::get` returns `Option<Vec<u8>>` — cached value is raw bytes; `Body::from(cached)` accepts `Vec<u8>` directly; TTL is milliseconds (not seconds); `cache::set` third argument is `Option<u64>` — pass `Some(ttl_ms)` to set expiry, `None` for no expiry
