<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: 81145a9a43ec499240c687bd49376ab20c72b11c
      updated: 2026-07-23
-->

---
type: feature
app_type: http
languages: [javascript]
capabilities: [streaming]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/streaming
---

# Feature: Streaming Response

## When to Use

Use this pattern when the app must send a chunked HTTP response instead of buffering the full body before responding. Typical cases: server-sent events, progressive output, long-poll-style data feeds.

## Key APIs

### `ReadableStream`

```js
new ReadableStream({
  async start(controller) { ... }
})
```

- `start(controller)` — called once when the stream is created; write all enqueue logic here
- `controller.enqueue(chunk)` — pushes a `Uint8Array` chunk to the stream; call inside a loop to produce multiple chunks
- `controller.close()` — signals end-of-stream; **required** for the response to terminate cleanly

### `TextEncoder`

```js
const encoder = new TextEncoder();
encoder.encode(string) // → Uint8Array
```

Converts string chunks to the `Uint8Array` payload expected by `controller.enqueue`. Instantiate once and reuse inside the `start` closure.

### `Response` with stream body

```js
new Response(stream, {
  status: 200,
  headers: { 'content-type': 'text/plain; charset=utf-8' }
})
```

Pass the `ReadableStream` instance directly as the first argument. No buffering occurs — chunks are forwarded as they are enqueued.

### Timed chunk spacing

```js
await new Promise((resolve) => { setTimeout(resolve, 200); });
```

Wraps `setTimeout` in a `Promise` to create an async delay between chunks. Use inside an `async start` function with `await`. Long-running streams must respect the runtime's request-handling time budget — avoid delays that exceed platform limits.

## Complete Example

```js
function app(event) {
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    async start(controller) {
      for (let i = 0; i < 5; i++) {
        await new Promise((resolve) => { setTimeout(resolve, 200); });
        controller.enqueue(encoder.encode(`chunk ${i}\n`));
      }
      controller.close();
    },
  });

  return new Response(stream, {
    status: 200,
    headers: { 'content-type': 'text/plain; charset=utf-8' },
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

## Build

```json
"scripts": {
  "build": "fastedge-build src/index.js dist/streaming.wasm"
}
```

Entry point: `src/index.js`. Output: `dist/streaming.wasm`. Requires `@gcoredev/fastedge-sdk-js` ^2.2.2.

## Constraints

- `controller.close()` must be called after all chunks are enqueued; omitting it leaves the response open indefinitely
- Chunk payload must be `Uint8Array`; use `TextEncoder.encode` to convert strings
- `async start` is the correct source pattern — chunks produced in `start`, not `pull`
- Timed delays must stay within the platform's request-handling time budget

## See Also

- http-base skeleton reference
- deploy skill reference
- fastedge-build CLI reference
- FastEdge-sdk-js SDK reference

## Source Material

### FILE: examples/streaming/src/index.js

```js
function app(event) {
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    async start(controller) {
      for (let i = 0; i < 5; i++) {
        // eslint-disable-next-line no-await-in-loop
        await new Promise((resolve) => { setTimeout(resolve, 200); });
        controller.enqueue(encoder.encode(`chunk ${i}\n`));
      }
      controller.close();
    },
  });

  return new Response(stream, {
    status: 200,
    headers: { 'content-type': 'text/plain; charset=utf-8' },
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```


### FILE: examples/streaming/package.json

```json
{
  "name": "fastedge-example-streaming",
  "version": "1.0.0",
  "description": "FastEdge JS example: streaming response with ReadableStream",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/streaming.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.2.2"
  }
}
```
