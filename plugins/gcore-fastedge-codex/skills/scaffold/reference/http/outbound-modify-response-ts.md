<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: 36cf4c4af034a19e45e5a92d06aa95adeb9b1ff9
      updated: 2026-06-11
-->

---
type: feature
app_type: http
languages: [javascript]
capabilities: [fetch, transform, proxy]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/outbound-modify-response
---

# Feature: outbound-modify-response

## When to Use

Use this pattern when the edge worker must proxy an upstream origin, transform the response body (filter fields, paginate, rename keys, slice arrays), and return a freshly constructed response to the client — without forwarding the upstream `Response` object directly (which would inherit upstream headers and status codes).

---

## Complete Example

```javascript
async function app(event) {
  const outboundResponse = await fetch('http://jsonplaceholder.typicode.com/users');
  const users = await outboundResponse.json();
  return new Response(
    JSON.stringify({
      users: users.slice(0, 5),
      total: 5,
      skip: 0,
      limit: 30,
    }),
    {
      status: 200,
      headers: {
        'content-type': 'application/json',
      },
    },
  );
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

---

## Pattern Breakdown

### 1. Outbound fetch

```javascript
const outboundResponse = await fetch('http://jsonplaceholder.typicode.com/users');
```

- `fetch(url)` — issues an outbound HTTP GET request from the edge worker to the upstream origin.
- URL is a literal string; substitute with your own origin URL.
- Returns a `Response` object; must be `await`-ed.

### 2. Parse upstream body

```javascript
const users = await outboundResponse.json();
```

- `response.json()` — reads the response body stream and deserialises it as JSON.
- Must be `await`-ed; body can only be consumed once.
- Result type: any JSON-deserialisable value (here: an array of user objects).

### 3. Transform the data

```javascript
users.slice(0, 5)
```

- Slice the upstream array to retain only the first 5 elements.
- Wrap the sliced array in a paged envelope: `{ users, total, skip, limit }`.
- Substitute array operations and envelope shape as required for your use case.

### 4. Construct a fresh Response

```javascript
return new Response(
  JSON.stringify({ users: users.slice(0, 5), total: 5, skip: 0, limit: 30 }),
  {
    status: 200,
    headers: {
      'content-type': 'application/json',
    },
  },
);
```

- `new Response(body, init)` — constructs a new response; does NOT inherit upstream headers or status.
- `body` — serialised string produced by `JSON.stringify(...)`.
- `init.status` — explicit HTTP status code (integer).
- `init.headers['content-type']` — must be set explicitly when the body is JSON; upstream content-type is not forwarded.

---

## Key Constraints

- The upstream `Response` object is NOT returned directly; a new `Response` is always synthesised so downstream clients do not inherit unintended upstream headers or status codes.
- `response.json()` consumes the body stream; it cannot be re-read after awaiting.
- `fetch` is available globally in the FastEdge JS runtime — no import required.
- `addEventListener('fetch', ...)` is the required entry point; the handler must call `event.respondWith(promise)`.

---

## Build Configuration

From `package.json`:

```json
{
  "name": "fastedge-example-outbound-modify-response",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/outbound-modify-response.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.2.2"
  }
}
```

- Entry point: `src/index.js`
- Output: `dist/outbound-modify-response.wasm`
- Build tool: `fastedge-build` (provided by `@gcoredev/fastedge-sdk-js`)
- Module format: ESM (`"type": "module"`)

---

## See Also

- http-base skeleton reference
- sdk-reference-js (fetch API, Response constructor, addEventListener)
- deploy skill reference (uploading and registering the compiled WASM binary)
- outbound-fetch feature blueprint (fetch without body transformation)
