# Synthesis Instructions: cors-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/cors-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [cors]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/cors
```

## Example-specific extraction hints
- Extract origin validation from `stream_context.headers.request.get("Origin")` against `getEnv("ALLOWED_ORIGINS")` — comma-separated list, `"*"` for wildcard
- Show `isOriginAllowed(origin, allowedOrigins)` as a class **private method** (not a closure) — AssemblyScript has no closures over mutable state and nested functions miss default args under indirect dispatch
- Show response-phase header injection in `onResponseHeaders`: `Access-Control-Allow-Origin` (echoed origin or `*`), `Vary: Origin`, optional `Access-Control-Expose-Headers` from `EXPOSE_HEADERS` env
- Note that OPTIONS preflights are handled by the FastEdge edge layer **before** this hook fires — do NOT attempt preflight handling here (this differs from the Rust SDK example)
- Env var configuration: `ALLOWED_ORIGINS` (required), `EXPOSE_HEADERS` (optional)
- No new dependencies beyond the base skeleton
- "When to Use" hint: user wants to add CORS response headers based on a configurable allowed-origin list at the CDN layer
