# Synthesis Instructions: secret-rollover-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/secret-rollover-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [secrets, secret-rollover]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/secret_rollover
```

## Example-specific extraction hints
- API focus: `fastedge::secret::get(name)` for the current (latest) slot, `fastedge::secret::get_effective_at(name, slot: u32)` for slot-based historical lookup
- Show the slot-as-timestamp pattern: read `x-slot` header, fall back to `SystemTime::now()` unix timestamp cast to `u32`; explain greatest-matching-slot rule
- `serde_json` and `fastedge` crate must be added to dependencies
- "When to Use" hint: user needs to support secret rotation where tokens issued at different times must be validated against the secret value that was active when the token was issued
