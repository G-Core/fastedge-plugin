# Synthesis Instructions: kv-store-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/kv-store-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [kv-store]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/key_value
```

## Example-specific extraction hints
- Extract `fastedge::proxywasm::key_value::Store` API — `Store::open(name)` returns `Result<Store, Error>`
- Show all operations: `store.get(key)` returns `Result<Option<Vec<u8>>, Error>`, `store.scan(pattern)` returns `Result<Vec<String>, Error>`, `store.zrange_by_score(key, min, max)` returns `Result<Vec<(Vec<u8>, f64)>, Error>`, `store.zscan(key, pattern)` returns `Result<Vec<(Vec<u8>, f64)>, Error>`, `store.bf_exists(key, item)` returns `Result<bool, Error>`
- Show query parameter parsing pattern for dispatching actions
- Show JSON response formatting with `serde_json::json!` macro
- Show response body replacement: `on_http_response_headers` to remove content-length and set content-type, `on_http_response_body` with `end_of_stream` check and `self.set_http_response_body()`
- CDN pattern: uses response hooks (`on_http_response_headers` + `on_http_response_body`) to replace the upstream response body with KV data
- "When to Use" hint: user wants to query a key-value store for data lookups, sorted sets, bloom filters, or pattern scanning at the CDN layer
