# Synthesis Instructions: kv-store-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/kv-store-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [kv-store]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/key_value
```

## Example-specific extraction hints
- Extract KV Store API: `key_value::Store::open()`, `get()`, and any write operations
- Show WASI-specific patterns if different from the basic HTTP SDK
- "When to Use" hint: user wants to store/retrieve data using a key-value store in a Rust HTTP WASI app
