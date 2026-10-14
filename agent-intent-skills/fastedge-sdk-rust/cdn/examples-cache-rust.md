# Synthesis Instructions: examples-cache-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-cache-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::proxywasm::cache`. It has free functions only, with no named stores and no handle. Values are local to the PoP, so writes in one PoP are not visible in another.
  - `cache::get(key: &str)` → `Result<Option<Vec<u8>>, Error>`. Returns `None` for missing keys; this is not an error.
  - `cache::set(key: &str, value: &[u8], ttl_ms: Option<u64>)` → `Result<(), Error>`. `None` gets the host's default TTL. It does not mean "no expiry", even though the source comments say so. Overwrites an existing value.
  - `cache::delete(key: &str)` → `Result<(), Error>`. A missing key is a no-op.
  - `cache::exists(key: &str)` → `Result<bool, Error>`
  - `cache::incr(key: &str, delta: i64)` → `Result<i64, Error>`. Atomic. A missing key starts at `0`. `delta` may be negative. Returns the new value.
  - `cache::expire(key: &str, ttl_ms: u64)` → `Result<bool, Error>`. Returns `false` when the key does not exist.
  - `cache::purge()` → `Result<u64, Error>`. Deletes every key owned by the app and returns the count.
  - `cache::purge_prefix(prefix: &str)` → `Result<u64, Error>`. Deletes the app's keys that start with `prefix` and returns the count.
- Show `Vec<u8>` to string conversion with `String::from_utf8_lossy(&value)` for `get` results.
- Show `serde_json::json!` for JSON response formatting. `Option<u64>` serialises as `null` when no TTL is given.
- Common patterns:
  - Parse `request.query` with `querystring::querify` and dispatch on `action`. This is a demo only: it lets any client call mutating actions, including app-wide `purge`. Say that real apps must gate those behind authorization or a trusted route.
  - Use `incr` for counters and rate limiting. The counts are per PoP, so a limit applies per PoP, not globally. Every `incr` key needs an `expire`, and when to call it depends on the key shape (see the `incr` gotcha below). Do not tell readers to call `expire` after every `incr` on a fixed key: that keeps pushing the deadline out, so the window never resets under steady traffic.
  - `set(..., Some(ttl))` with `ttl > 0` already sets the expiry. `Some(0)` behaves like `None` and gets the host default. Use `expire` separately only to extend an existing key's expiry on access (sliding expiry).
  - Use `purge_prefix` to invalidate a group of keys.
- Error path: `response.status` is set in `on_http_response_body`, after the headers have gone out, so it is advisory only. The JSON error body is the real error signal.
- Show response body replacement: set `content-type` in `on_http_response_headers`, then replace the body in `on_http_response_body` with `self.set_http_response_body(0, body_size, bytes)` after `end_of_stream`.
- Gotchas:
  - The TTL and `incr` behaviour below was measured on HTTP apps. Say that it is not yet verified for CDN (proxy-wasm) apps, and do not present it as confirmed CDN behaviour.
  - TTLs are in milliseconds, not seconds.
  - The host silently clamps every `set` TTL to a deployment ceiling, 4 days by default, and that ceiling also applies when no TTL is passed. No entry outlives ~4 days, and there is no way to read a key's TTL.
  - `incr` sets no TTL and does not index the key. `incr` keys escape both the default TTL and `purge`/`purge_prefix`, so every `incr` key needs an `expire`. For when to call it (fixed key vs time-bucketed key), refer to the FastEdge storage platform reference by topic name rather than restating it.
  - `expire` returns `false` for an absent key and `Err` for a failure. Do not treat them the same.
  - Keys are app-scoped automatically, so you don't need to add a prefix to avoid collisions with other apps.
  - `incr` errors if the stored value is not an integer.
  - Values are `Vec<u8>` and must be decoded.
  - Error variants are `AccessDenied`, `InternalError`, and `Other(String)`.
  - This cache is unrelated to CDN HTTP caching. To control edge caching of responses, use `Cache-Control` headers (see the CDN cache-control example, by topic name).
