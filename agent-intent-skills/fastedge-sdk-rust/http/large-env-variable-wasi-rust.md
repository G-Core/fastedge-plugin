# Synthesis Instructions: large-env-variable-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/large-env-variable-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [large-env-variable, dictionary]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/large_env_variable
```

## Example-specific extraction hints
- API focus: `fastedge::dictionary::get(name)` — returns `Option<String>`, use `unwrap_or_default()` for safe fallback
- Show the contrast with `std::env::var()`: dictionary API is required only when values may exceed 64 KB; otherwise prefer env::var
- The `fastedge` crate must be added to dependencies alongside `wstd`; show this in the deps section
- "When to Use" hint: user wants to read a large configuration payload (e.g. JSON blob) stored as an environment variable that may exceed the 64 KB WASI environment variable size limit
