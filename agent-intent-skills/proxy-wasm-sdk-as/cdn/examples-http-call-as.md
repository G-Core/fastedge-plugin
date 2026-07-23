# Synthesis Instructions: examples-http-call-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-http-call-as.md`

## Example-specific extraction hints
- API focus: `RootContext.httpCall(upstream, headers, body, trailers, timeoutMs, ctx, callback)` returning `WasmResultValues`; `makeHeaderPair` for pseudo and custom headers; `get_buffer_bytes(BufferTypeValues.HttpCallResponseBody, ...)`; `stream_context.headers.http_callback.get(name)`
- Show the dispatch-from-root pattern: `(this.root_context as <Root>).httpCall(...)` — request-stream contexts dispatch via their owning root
- Show the re-dispatch latch (instance `bool` field) — first `onRequestHeaders` returns `StopIteration`, the host re-enters the hook after the callback fires and the latch makes the second invocation return `Continue`
- Show callback signature `(ctx: BaseContext, hdrs: u32, bodySize: usize, trls: u32): void` — `hdrs == 0` indicates the call failed; decode the body with `String.UTF8.decode`
- Gotchas: AssemblyScript has no closures over mutable state — capture state on the context instance or via `set_property`/`get_property`; instance state survives the re-entry within the same context but not across the nginx→core-proxy hop; tune the `timeoutMs` (the example uses 3000ms for cold DNS); no try/catch — check `WasmResultValues.Ok` explicitly
