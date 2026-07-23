# Synthesis Instructions: bloom-filter-denylist-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/bloom-filter-denylist-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [bloom-filter, kv-store, ip-denylist]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/bloom_filter_denylist
```

## Example-specific extraction hints
- API focus: `fastedge::key_value::Store::open(&name)`, `store.bf_exists(key, value)` — the bloom-filter membership check
- Show the `fastedge::key_value::Error::AccessDenied` match arm for permission-failure handling
- Show client IP extraction from `x-real-ip` with fallback to `x-forwarded-for` (first comma-delimited token)
- Show the `json_response` helper using `serde_json::json!` macro
- New dependencies vs base skeleton: `fastedge = "0.4"`, `serde_json = "1"`
- "When to Use" hint: user wants to block requests from a pre-populated IP denylist stored as a bloom filter in FastEdge KV
