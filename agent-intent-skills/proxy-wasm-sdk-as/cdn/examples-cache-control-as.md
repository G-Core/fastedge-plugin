# Synthesis Instructions: examples-cache-control-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-cache-control-as.md`

## Example-specific extraction hints
- API focus: `get_property("response.status")` (2-byte big-endian `u16`, decode via `Uint8Array.wrap`), `stream_context.headers.response.get("Content-Type")`, `stream_context.headers.response.replace("Cache-Control", ...)`, `stream_context.headers.response.add("Vary", ...)`; `getEnv` for tunable max-ages
- Show the content-type-tiered policy: errors (< 200 or ≥ 400) → `no-store`; static (image/, font/, application/javascript, text/css, text/javascript, application/wasm) → `public, max-age=<STATIC_MAX_AGE>, immutable`; HTML → `public, max-age=<HTML_MAX_AGE>, must-revalidate` + `Vary: Accept-Encoding`; JSON/XML → `private, max-age=<API_MAX_AGE>, must-revalidate` + `Vary: Accept, Authorization` (or `no-cache, no-store, must-revalidate` when `API_MAX_AGE==0`); else `public, max-age=600`
- Show the empty-string default pattern (`raw === "" ? default : raw`) — do NOT use `||` because in AssemblyScript the empty string is pointer-truthy
- Gotchas: response status is binary `u16` (not a string); use `replace` (not `add`) on `Cache-Control` so upstream headers are overwritten; helpers like `isStaticAsset` must be class private methods (no closures, no default args on nested functions); `getEnv` returns empty string (not null) when unset
