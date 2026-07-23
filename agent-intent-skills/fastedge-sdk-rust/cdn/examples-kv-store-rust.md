# Synthesis Instructions: examples-kv-store-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-kv-store-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::proxywasm::key_value::Store` — `Store::open(name)` returns `Result<Store, Error>`, then operations:
  - `store.get(key)` → `Result<Option<Vec<u8>>, Error>` (None for missing keys, not an error)
  - `store.scan(pattern)` → `Result<Vec<String>, Error>` (key listing by glob pattern)
  - `store.zrange_by_score(key, min, max)` → `Result<Vec<(Vec<u8>, f64)>, Error>` (sorted set range query)
  - `store.zscan(key, pattern)` → `Result<Vec<(Vec<u8>, f64)>, Error>` (sorted set pattern scan)
  - `store.bf_exists(key, item)` → `Result<bool, Error>` (bloom filter membership check)
- Show `Vec<u8>` to string conversion with `String::from_utf8_lossy(&value)` for get results
- Show `serde_json::json!` for JSON response formatting
- Common patterns: parse query parameters to dispatch to different KV operations, return JSON responses
- Show response body replacement: set content-type in `on_http_response_headers`, replace body in `on_http_response_body` with `self.set_http_response_body(0, body_size, bytes)`
- Gotchas: `get` returns `None` for missing keys, all values are `Vec<u8>` (must decode), `open` takes a store name configured in the platform, sorted set tuples are `(Vec<u8>, f64)` for value+score
