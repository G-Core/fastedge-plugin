# Synthesis Instructions: streaming-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/streaming-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [streaming]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/streaming
```

## Example-specific extraction hints
- Extract the `ReadableStream` constructor with an `async start(controller)` source: the chunks are produced inside `start`, not via `pull` — this is the recommended pattern for time-spaced writes
- Preserve `controller.enqueue(encoder.encode(chunk))` plus `controller.close()` at the end of the loop — the close is required for the response to terminate cleanly
- Show `new TextEncoder()` reused inside the closure to convert string chunks into the `Uint8Array` payload the stream expects
- Preserve the `setTimeout`-based delay pattern (wrapped in `new Promise`) so users see how to space chunks in real time; call out that long-running streams must respect the runtime's request-handling time budget
- Show the `new Response(stream, { status: 200, headers: { 'content-type': 'text/plain; charset=utf-8' } })` construction — the `ReadableStream` is passed directly as the body
- "When to Use" hint: user wants to send a chunked HTTP response (server-sent events, progressive output, long-poll-style data feed) instead of buffering the full body before responding
