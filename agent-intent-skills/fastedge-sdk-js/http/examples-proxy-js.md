# Synthesis Instructions: examples-proxy-js.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-proxy-js.md`

## Source note
The source `docs/PROXY_PATTERNS.md` is hand-authored in the SDK repo (not produced by `generate-docs.sh`). It is already polished — preserve content faithfully. Apply formatting/cross-referencing rules from the base instructions but do not restructure or invent new patterns.

## Example-specific extraction hints
- API focus: `fetch(url, options)` for outbound, `new Response(body, init)` for forwarding, `request.arrayBuffer()` / `c.req.arrayBuffer()` for body forwarding.
- Simple proxy: forward request to upstream and return the streamable Response without buffering. Note that `return response` streams body chunks.
- JSON transform: from `examples/outbound-modify-response/`. Read body with `await upstream.json()`, modify, return new Response. Call out that `.json()` consumes the body — clone first if both copies are needed.
- Hono variant: `app.all("/api/*", ...)` with `c.req.raw.headers` for inbound headers and `c.req.arrayBuffer()` for body.
- Header manipulation: strip hop-by-hop headers (connection, keep-alive, transfer-encoding) before forwarding; add diagnostic headers on the way back. Show `new Response(upstream.body, ...)` streaming pattern.
- KV-backed cache: `KvStore.open()` may return null; check before calling `.get()`. KV is read-only from app code — writes happen via portal/API.
- Operational notes: outbound budget per invocation (5 Basic / 20 Pro), execution time budget, body size limits, redirect handling (`redirect: "manual"`).
- Gotchas focus: body consumption (`.json()`/`.text()`/`.arrayBuffer()` are one-shot), buffering vs streaming for large responses, hop-by-hop header forwarding correctness.
