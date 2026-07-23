# Synthesis Instructions: request-inspection-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/request-inspection-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [debugging, request]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/request-inspection
```

## Example-specific extraction hints
- Extract the diagnostic echo pattern: destructure `{ request, client }` from `event`, then read `request.method`, `request.url`, `client.address`, and iterate `request.headers` as `[name, value]` pairs
- Preserve the headers iteration form `for (const [name, value] of request.headers)` — this is the idiomatic Web Fetch API iterator and reveals every header the runtime is forwarding
- Show the response as a plain-text body (`content-type: text/plain; charset=utf-8`) so the output is human-readable when hit with curl
- Call out that `event.client.address` is the FastEdge `ClientInfo` extension and yields the originating client IP after any reverse-proxy unwrapping
- "When to Use" hint: user wants a throwaway diagnostic worker that echoes the incoming method, URL, client IP, and every header — useful for verifying header forwarding, geo-IP propagation, or surfacing what the edge actually sees
