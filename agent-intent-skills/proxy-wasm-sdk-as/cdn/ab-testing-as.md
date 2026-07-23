# Synthesis Instructions: ab-testing-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/ab-testing-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [ab-testing, cookies, traffic-splitting]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/abTesting
```

## Example-specific extraction hints
- Extract cookie parsing as a class **private method** (`getCookieValue(cookieHeader, name)`) — splits on `;`, matches the `name=` prefix; no closures
- Show variant assignment with `getCurrentTime()` (`u64` ms) — `now % 2 == 0 ? "A" : "B"` for a 50/50 split
- Show the request-URL rebuild from decomposed properties (`request.scheme`, `request.host`, `request.query`) prepended with the variant path — do NOT splice the original full URL string (path can collide with host substrings; query may be lost)
- Show URL rewrite via `set_property("request.url", String.UTF8.encode(newUrl))`
- Show cross-hook coordination via request headers: `onRequestHeaders` adds `X-Experiment` and `X-Variant`; `onResponseHeaders` recovers `X-Variant` via `stream_context.headers.request.get("X-Variant")` (instance state does not survive the nginx→core-proxy hop) and emits `Set-Cookie: fe_exp_<name>=<variant>; Path=/; Max-Age=86400; SameSite=Lax`
- Env vars: `EXPERIMENT_NAME`, `VARIANT_A_PATH`, `VARIANT_B_PATH`
- Import `getCurrentTime` from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`
- "When to Use" hint: user wants to split traffic between A/B variants using cookie-stickiness and path rewriting at the CDN layer
