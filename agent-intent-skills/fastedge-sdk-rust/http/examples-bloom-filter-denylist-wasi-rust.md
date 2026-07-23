# Synthesis Instructions: examples-bloom-filter-denylist-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-bloom-filter-denylist-wasi-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::key_value::Store::open(&store_name)` returns `Result<Store, StoreError>`; `store.bf_exists(BLOOM_KEY, ip)` returns `Result<bool, StoreError>` — show both signatures and import paths
- Common patterns: matching `StoreError::AccessDenied` separately from other errors; extracting client IP with `x-real-ip` → `x-forwarded-for` fallback; returning JSON error bodies via a `json_response(status, serde_json::Value)` helper
- Gotchas: bloom filter is read-only from the handler — it must be populated out of band; bloom filter membership is probabilistic — false positives are expected (acceptable over-blocking) but false negatives cannot occur; the filter key (`blocked-ips`) is hardcoded; `DENYLIST_STORE` env var must name the KV store that holds the filter
