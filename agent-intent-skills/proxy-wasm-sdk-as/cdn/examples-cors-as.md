# Synthesis Instructions: examples-cors-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-cors-as.md`

## Example-specific extraction hints
- API focus: `stream_context.headers.request.get("Origin")` and `stream_context.headers.response.add(...)`, plus `getEnv("ALLOWED_ORIGINS")` and `getEnv("EXPOSE_HEADERS")`
- Show origin matching: `"*"` wildcard, exact match against comma-separated list, `.trim()` on each entry
- Show the two-hook pattern: `onRequestHeaders` reads/validates origin (logging only), `onResponseHeaders` injects `Access-Control-Allow-Origin`, `Vary: Origin`, and optional `Access-Control-Expose-Headers`
- Note explicitly: **OPTIONS preflights are answered by the FastEdge edge layer before the hook fires** — examples should not attempt to short-circuit preflights from the wasm filter
- Gotchas: no closures — origin helper must be a class private method; empty-string (not null) check on `getEnv`; when echoing the origin set `Vary: Origin` so caches do not collapse responses across origins; `remove` on a header sets it to empty string (FastEdge CDN platform limitation, not nginx) — when checking absence test for both missing and empty
