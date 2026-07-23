# Synthesis Instructions: examples-ab-testing-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-ab-testing-as.md`

## Example-specific extraction hints
- API focus: `stream_context.headers.request.get("Cookie")` for cookie reads, `getCurrentTime()` (`u64` ms) for variant entropy, `set_property("request.url", ...)` for path rewrite, `stream_context.headers.response.add("Set-Cookie", ...)` for sticky-session persistence
- Show the two-hook flow: `onRequestHeaders` reads cookie / assigns variant / rewrites `request.url` / adds `X-Experiment` and `X-Variant` request headers; `onResponseHeaders` recovers the variant from the request header (instance state does NOT survive nginx→core-proxy) and writes `Set-Cookie`
- Show URL rebuild from decomposed properties (`request.scheme`, `request.host`, `request.query`) — do not string-splice the original URL
- Cookie convention: `fe_exp_<EXPERIMENT_NAME>=<A|B>; Path=/; Max-Age=86400; SameSite=Lax`
- Gotchas: AssemblyScript has no closures — cookie parsing must be a class private method; cross-hook state survives only via headers/properties, not via instance fields; `getCurrentTime` returns milliseconds; `getEnv` returns empty string (not null) when unset
