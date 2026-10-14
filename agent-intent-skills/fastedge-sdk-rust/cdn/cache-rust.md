# Synthesis Instructions: cache-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/cache-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [cache]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/cache
```

## Example-specific extraction hints
- Extract the `fastedge::proxywasm::cache` module API. It is a set of free functions, with no store handle and no `open()`. Every key is scoped to the calling application.
- Show all operations:
  - `cache::get(key: &str)` returns `Result<Option<Vec<u8>>, Error>`
  - `cache::set(key: &str, value: &[u8], ttl_ms: Option<u64>)` returns `Result<(), Error>`
  - `cache::delete(key: &str)` returns `Result<(), Error>`
  - `cache::exists(key: &str)` returns `Result<bool, Error>`
  - `cache::incr(key: &str, delta: i64)` returns `Result<i64, Error>`
  - `cache::expire(key: &str, ttl_ms: u64)` returns `Result<bool, Error>`
  - `cache::purge()` returns `Result<u64, Error>`
  - `cache::purge_prefix(prefix: &str)` returns `Result<u64, Error>`
- TTL wording: the source comments and README say that omitting `ttl` means "no expiry". **Do not repeat that.**
  - Describe `None` as "the host default TTL (~4 days)", not "never expires". The host clamps every `set` to a deployment ceiling (default 4 days), whether or not a TTL is passed.
  - State that this was measured on HTTP apps and is not yet verified for CDN (proxy-wasm) apps.
- `incr` keys need their own `expire`: `incr` sets no TTL and does not index the key, so `purge` and `purge_prefix` miss it (also measured on HTTP apps). Refer to the FastEdge storage platform reference for the `expire` pattern, by topic name rather than file path.
- Show the query-parameter dispatch pattern: read `request.query` with `self.get_property(vec!["request.query"])`, parse it with `querystring::querify`, and `match` on `action`, which defaults to `get`.
- Show the per-action handler shape `fn handle_x(&self, params) -> Result<String, String>`, which returns either the JSON body or an error message.
- Show JSON response formatting with the `serde_json::json!` macro.
- Show response body replacement:
  - In `on_http_response_headers`, remove `content-length` and set `content-type: application/json`.
  - In `on_http_response_body`, return `Action::Pause` until `end_of_stream`, then call `self.set_http_response_body(0, body_size, bytes)`.
- Show error handling: `send_error` sets `response.status` with `self.set_property` and writes a `{"error": ...}` body.
  - Note that the status is advisory only. It is set in `on_http_response_body`, after the response headers have gone out, so the origin status reaches the client. The JSON error body is the real error signal.
  - Do not invent a different status encoding. Show the call as it appears in the source.
- Dependencies to add: `fastedge` with `features = ["proxywasm"]`, `querystring`, and `serde_json`. The base skeleton already provides `proxy-wasm`.
- CDN pattern: the response hooks (`on_http_response_headers` + `on_http_response_body`) replace the upstream response body with the result of the cache operation.
- "When to Use" hint: the user wants app-scoped, TTL-based key/value storage at the CDN layer, such as counters, rate limiting, or short-lived memoisation.
  - This is not HTTP response caching (`Cache-Control`); that is the `cache-control` blueprint.
  - This is not read-mostly named stores; that is the `kv-store` blueprint.
