# Synthesis Instructions: examples-cache-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-cache-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::proxywasm::cache`. It has free functions only, with no named stores and no handle.
  - `cache::get(key)` → `Result<Option<Vec<u8>>, Error>`. Returns `None` for missing keys; this is not an error.
  - `cache::set(key, value: &[u8], ttl_ms: Option<u64>)` → `Result<(), Error>`. `None` gets the host's default TTL. It does not mean "no expiry", even though the source comments say so. Overwrites an existing value.
  - `cache::delete(key)` → `Result<(), Error>`. A missing key is a no-op.
  - `cache::exists(key)` → `Result<bool, Error>`
  - `cache::incr(key, delta: i64)` → `Result<i64, Error>`. Atomic. A missing key starts at `0`. `delta` may be negative. Returns the new value.
  - `cache::expire(key, ttl_ms: u64)` → `Result<bool, Error>`. Returns `false` when the key does not exist.
  - `cache::purge()` → `Result<u64, Error>`. Deletes every key owned by the app and returns the count.
  - `cache::purge_prefix(prefix)` → `Result<u64, Error>`. Deletes the app's keys that start with `prefix` and returns the count.
- Show `Vec<u8>` to string conversion with `String::from_utf8_lossy(&value)` for `get` results.
- Show `serde_json::json!` for JSON response formatting. `Option<u64>` serialises as `null` when no TTL is given.
- Common patterns:
  - Parse `request.query` with `querystring::querify` and dispatch on `action`.
  - Use `incr` for counters and rate limiting, always followed by `expire`.
  - Use `set` with a TTL, then `expire`, for sliding expiry.
  - Use `purge_prefix` to invalidate a group of keys.
- Show response body replacement: set `content-type` in `on_http_response_headers`, then replace the body in `on_http_response_body` with `self.set_http_response_body(0, body_size, bytes)` after `end_of_stream`.
- Gotchas:
  - TTLs are in milliseconds, not seconds.
  - The host silently clamps every `set` TTL to a deployment ceiling, 4 days by default, and that ceiling also applies when no TTL is passed. No entry outlives ~4 days, and there is no way to read a key's TTL.
  - `incr` sets no TTL and does not index the key. `incr` keys escape both the default TTL and `purge`/`purge_prefix`, so every `incr` key needs an `expire`. For when to call it (fixed key vs time-bucketed key), point to `../platform/storage.md` rather than restating it.
  - `expire` returns `false` for an absent key and `Err` for a failure. Do not treat them the same.
  - Keys are app-scoped automatically, so you don't need to add a prefix to avoid collisions with other apps.
  - `incr` errors if the stored value is not an integer.
  - Values are `Vec<u8>` and must be decoded.
  - Error variants are `AccessDenied`, `InternalError`, and `Other(String)`.
  - This cache is unrelated to CDN HTTP caching. To control edge caching of responses, use `Cache-Control` headers (see `examples-cache-control-rust.md`).
