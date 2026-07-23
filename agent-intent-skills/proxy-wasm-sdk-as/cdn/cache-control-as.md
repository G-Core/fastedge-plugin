# Synthesis Instructions: cache-control-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/cache-control-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [cache-control, caching]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/cacheControl
```

## Example-specific extraction hints
- Extract response-status decoding: `get_property("response.status")` returns a 2-byte big-endian `ArrayBuffer` — decode via `Uint8Array.wrap(buf)` and `(u32(bytes[0]) << 8) | u32(bytes[1])`. NOT a UTF-8 string.
- Show content-type-tiered cache policy keyed off `stream_context.headers.response.get("Content-Type")`:
  - errors (status < 200 or ≥ 400) → `Cache-Control: no-store` (short-circuit)
  - static assets (image/, font/, application/javascript, text/css, text/javascript, application/wasm) → `public, max-age=<STATIC_MAX_AGE>, immutable`
  - text/html → `public, max-age=<HTML_MAX_AGE>, must-revalidate` plus `Vary: Accept-Encoding`
  - JSON/XML → `no-cache, no-store, must-revalidate` when `API_MAX_AGE==0`, else `private, max-age=<API_MAX_AGE>, must-revalidate` plus `Vary: Accept, Authorization`
  - default → `public, max-age=600`
- Show env vars with defaults (`STATIC_MAX_AGE=31536000`, `HTML_MAX_AGE=3600`, `API_MAX_AGE=0`); use `rawValue === "" ? default : rawValue` (empty-string check, not `||` — the AS empty-string is pointer-truthy)
- Show `isStaticAsset(contentType)` as a class **private method** (no closures)
- Show `replace("Cache-Control", ...)` (not `add`) so existing upstream headers are overwritten
- All logic in `onResponseHeaders`; no new dependencies beyond the base skeleton
- "When to Use" hint: user wants to set content-type-aware `Cache-Control` headers on responses at the CDN layer
