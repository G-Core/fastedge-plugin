# Synthesis Instructions: variables-and-secrets-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/variables-and-secrets-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [env-variables, secrets]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/variables_and_secrets
```

## Example-specific extraction hints
- API focus: `std::env::var("NAME")` for plain environment variables; `fastedge::secret::get("NAME")` for secrets — returns `Result<Option<String>, ...>`; handle both `Ok(Some(v))` and all other cases with `_ =>` fallback
- Show the two-step pattern: env var with `env::var(...).unwrap_or_default()` and secret with `match secret::get(...) { Ok(Some(v)) => v, _ => String::new() }`
- `fastedge` crate must be added to dependencies
- "When to Use" hint: user wants to read both plain environment variables and encrypted secrets in the same app and use them in a response or business logic
