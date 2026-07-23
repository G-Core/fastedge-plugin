# Synthesis Instructions: static-assets-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/static-assets-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [static-assets, path-routing]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/static_assets
```

## Example-specific extraction hints
- API focus: `include_str!("../assets/filename")` to embed text assets at compile time; `req.uri().path()` to route by request path; `wstd::http::StatusCode` for typed status codes
- Show the static `Asset` struct pattern: `content_type: &'static str`, `body: &'static str`; embed each asset as a named `static` constant; a `lookup(path)` function that matches paths to assets
- For binary assets mention `include_bytes!` as the counterpart to `include_str!`
- Files to Create section must include the `assets/` directory with placeholder `index.html`, `style.css`, `logo.svg`
- "When to Use" hint: user wants to embed static files (HTML, CSS, images) into the WASM binary at compile time and serve them by URL path, since WASM has no filesystem at runtime
