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
capabilities: [debugging, request]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/request-inspection
---

# Request Inspection (HTTP, JavaScript)

## When to Use

Use this pattern when you need a throwaway diagnostic worker that echoes the incoming method, URL, client IP, and every header. Useful for:
- Verifying header forwarding through intermediaries
- Confirming geo-IP or custom header propagation
- Surfacing exactly what the edge runtime receives from the client

## Full Example

```javascript
function app(event) {
  const { request, client } = event;

  const lines = [
    `Method: ${request.method}`,
    `URL: ${request.url}`,
    `Client: ${client.address}`,
    'Headers:',
  ];
  for (const [name, value] of request.headers) {
    lines.push(`    ${name}: ${value}`);
  }

  return new Response(`${lines.join('\n')}\n`, {
    headers: { 'content-type': 'text/plain; charset=utf-8' },
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

## Key Patterns

### Destructuring event properties

```javascript
const { request, client } = event;
```

- `request` — the incoming `Request` object (Web Fetch API)
- `client` — FastEdge `ClientInfo` extension object

### Reading request metadata

```javascript
request.method   // HTTP method string, e.g. "GET"
request.url      // Full request URL string
```

### Reading client IP

```javascript
client.address   // Originating client IP address string
```

`event.client.address` is a FastEdge `ClientInfo` extension. It yields the originating client IP after any reverse-proxy unwrapping performed by the edge runtime.

### Iterating headers

```javascript
for (const [name, value] of request.headers) {
  lines.push(`    ${name}: ${value}`);
}
```

`request.headers` implements the Web Fetch API `Headers` iterable interface. Iterating it as `[name, value]` pairs yields every header the runtime is forwarding to the handler. This is the idiomatic form for exhaustive header inspection.

### Plain-text response

```javascript
return new Response(`${lines.join('\n')}\n`, {
  headers: { 'content-type': 'text/plain; charset=utf-8' },
});
```

Setting `content-type: text/plain; charset=utf-8` makes the response human-readable when hit directly with curl or a browser.

## API Surface Used

| Symbol | Type | Source |
|---|---|---|
| `event.request` | `Request` (Web Fetch API) | FastEdge fetch event |
| `event.client` | `ClientInfo` | FastEdge extension |
| `event.client.address` | `string` | FastEdge `ClientInfo` property |
| `request.method` | `string` | Web Fetch API `Request` |
| `request.url` | `string` | Web Fetch API `Request` |
| `request.headers` | `Headers` (iterable) | Web Fetch API `Request` |
| `Response` | constructor | Web Fetch API |
| `addEventListener('fetch', ...)` | function | FastEdge runtime entrypoint |

## Build Configuration

```json
{
  "name": "fastedge-example-request-inspection",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/request-inspection.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.2.2"
  }
}
```

- Entry point: `src/index.js`
- Output: `dist/request-inspection.wasm`
- Build tool: `fastedge-build` (provided by `@gcoredev/fastedge-sdk-js`)

## Constraints

- `client.address` reflects the IP as seen after edge reverse-proxy unwrapping; it is not necessarily the raw TCP peer address
- `request.headers` iteration order is not guaranteed to match the wire order
- The response body is constructed entirely in memory; not suitable for large payloads

## See Also

- fastedge-sdk-js SDK reference
- http-base skeleton
- platform-overview (ClientInfo, fetch event lifecycle)
- best-practices (response construction, header handling)

## Source Material

### FILE: examples/request-inspection/src/index.js

```js
function app(event) {
  const { request, client } = event;

  const lines = [
    `Method: ${request.method}`,
    `URL: ${request.url}`,
    `Client: ${client.address}`,
    'Headers:',
  ];
  for (const [name, value] of request.headers) {
    lines.push(`    ${name}: ${value}`);
  }

  return new Response(`${lines.join('\n')}\n`, {
    headers: { 'content-type': 'text/plain; charset=utf-8' },
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

### FILE: examples/request-inspection/package.json

```json
{
  "name": "fastedge-example-request-inspection",
  "version": "1.0.0",
  "description": "FastEdge JS example: echo the incoming request for debugging",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/request-inspection.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.2.2"
  }
}
```
