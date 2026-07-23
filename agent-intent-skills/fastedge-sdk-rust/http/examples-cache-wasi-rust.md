# Synthesis Instructions: examples-cache-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-cache-wasi-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::cache::get(key: &str) -> Result<Option<Vec<u8>>>`, `fastedge::cache::set(key: &str, value: &[u8], ttl_ms: Option<u64>) -> Result<()>` — synchronous (no `.await` needed) despite the surrounding async handler
- Common patterns: `cache::get` on every request with `?` propagation; early return on cache hit with `x-cache: hit`; forward to origin on miss with `wstd::http::Client`; only cache `status.is_success()` responses; replay original headers alongside `x-cache: miss`
- Gotchas: `CACHE_TTL_MS` defaults to 60 000 ms when absent or unparseable — always document this fallback; the cache stores raw bytes (`Vec<u8>`), so the generator must use `body.contents().await?.to_vec()` before passing to `cache::set`; `ORIGIN_HOST` must be set or the handler errors immediately (no fallback)
