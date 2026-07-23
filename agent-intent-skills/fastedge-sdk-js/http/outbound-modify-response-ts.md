# Synthesis Instructions: outbound-modify-response-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/outbound-modify-response-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [fetch, transform, proxy]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/outbound-modify-response
```

## Example-specific extraction hints
- Extract the fetch-then-transform pattern: `await fetch(upstreamUrl)` → `await response.json()` → reshape → return a new `Response` with `JSON.stringify(...)`
- Preserve the upstream URL as a literal (`http://jsonplaceholder.typicode.com/users`) so the blueprint is runnable; users will substitute their own origin
- Show the JSON shape transformation: slice the upstream array (`users.slice(0, 5)`) and wrap in a paged envelope (`{ users, total, skip, limit }`)
- Use the explicit `new Response(body, { status, headers: { 'content-type': 'application/json' } })` form so the content-type header pattern is visible
- Do NOT re-use the upstream `Response` object directly — the blueprint synthesises a fresh response so downstream consumers do not inherit upstream headers/status by accident
- "When to Use" hint: user wants to proxy an origin response through the edge while reshaping the body (filtering fields, paginating, renaming keys) or rewriting headers before returning to the client
