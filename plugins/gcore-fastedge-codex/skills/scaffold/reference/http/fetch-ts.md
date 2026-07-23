<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: b78b2a80317bb632af88010816d3e54afd3bd72d
      updated: 2026-06-16
-->
---
type: feature
app_type: http
languages: [typescript, javascript]
capabilities: [fetch]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/downstream-fetch
---

# Feature: Downstream Fetch (HTTP JavaScript)

## When to Use

Use this blueprint when the user needs to make outbound HTTP requests from the edge to an external API or service. Common use cases: API proxying, data aggregation, origin fetching, third-party API calls.

## Dependencies to Add

No additional npm dependencies beyond the base skeleton. The `fetch` API is built into the FastEdge runtime.

## Files to Create

None. All logic lives in `src/index.js`.

## Files to Modify

### src/index.js

**No imports needed.** The `fetch` API is globally available.

**Replace handler body with:**

```javascript
async function app(event) {
  return await fetch('http://jsonplaceholder.typicode.com/users');
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

## API Details

### `fetch(url[, init])`

- Globally available — no import required.
- `url`: `string` — the downstream target URL (hardcoded or dynamically constructed from `event.request`).
- `init`: optional `RequestInit` object — supports `method`, `headers`, `body`, and other standard Fetch API fields.
- Returns: `Promise<Response>` — the downstream response, including status, headers, and body.
- Returning the `Response` object directly from the handler proxies status, headers, and body to the client unchanged.

### Error Handling

- Network errors (unreachable host, DNS failure) cause the returned `Promise` to reject. Wrap in `try/catch` to handle:

```javascript
async function app(event) {
  try {
    return await fetch('http://jsonplaceholder.typicode.com/users');
  } catch (err) {
    return new Response('Upstream fetch failed: ' + err.message, { status: 502 });
  }
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

## Build Notes

- Build with `fastedge-build src/index.js dist/downstream-fetch.wasm`.
- The `fetch` function is available globally in the FastEdge runtime — no import needed.
- The response from the downstream service is returned directly to the client (status, headers, and body are all proxied through).
- This is the simplest possible pattern for outbound HTTP. For more complex scenarios, inspect `event.request` to build dynamic downstream URLs, add headers, or transform the response before returning it.
- The downstream URL can be hardcoded or read from environment variables using `getEnv` (see the headers or geo-redirect examples for that pattern).
- SDK version is `^2.2.2` in `package.json`.

## Source Material

### FILE: examples/downstream-fetch/src/index.js

```javascript
async function app(event) {
  return await fetch('http://jsonplaceholder.typicode.com/users');
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

### FILE: examples/downstream-fetch/package.json

```json
{
  "name": "fastedge-example-downstream-fetch",
  "version": "1.0.0",
  "description": "FastEdge JS example: downstream HTTP fetch",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/downstream-fetch.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.2.2"
  }
}
```

### FILE: examples/outbound-fetch/src/index.js

```javascript
async function app(event) {
  return await fetch('http://jsonplaceholder.typicode.com/users');
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

### FILE: examples/outbound-fetch/package.json

```json
{
  "name": "fastedge-example-outbound-fetch",
  "version": "1.0.0",
  "description": "FastEdge JS example: outbound HTTP fetch",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/outbound-fetch.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.2.2"
  }
}
```
