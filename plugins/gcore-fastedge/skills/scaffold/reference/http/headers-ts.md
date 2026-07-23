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
languages: [typescript, javascript]
capabilities: [headers]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/headers
---

# Feature: Header Manipulation (HTTP JavaScript)

## When to Use

Use this blueprint when the user needs to read or modify HTTP request/response headers at the edge. Common use cases: adding custom headers, request enrichment, CORS headers, security headers, forwarding request headers to responses.

## Dependencies to Add

No additional npm dependencies beyond the base skeleton.

## Files to Create

None. All logic lives in `src/index.js`.

## Files to Modify

### src/index.js

**Add imports:**

```javascript
import { getEnv } from 'fastedge::env';
```

**Replace handler body with:**

```javascript
async function eventHandler(event) {
  const request = event.request;

  const customEnvVariable = getEnv('MY_CUSTOM_ENV_VAR') ?? '';

  const responseHeaders = new Headers(request.headers);
  responseHeaders.set('my-custom-header', customEnvVariable);

  return new Response('Returned all headers with a custom header added', {
    headers: responseHeaders,
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```

## Headers API

### Constructor

```javascript
new Headers(init?)
```

- `init` — optional. Accepts an existing `Headers` object, a plain object `{ [key: string]: string }`, or an array of `[string, string]` pairs.
- Passing an existing `Headers` object (e.g., `request.headers`) copies all entries into a new mutable instance.

### Methods

| Method | Signature | Description |
|---|---|---|
| `get` | `get(name: string): string \| null` | Returns the value of the named header, or `null` if not present. |
| `set` | `set(name: string, value: string): void` | Sets the header to the given value, replacing any existing value. |
| `append` | `append(name: string, value: string): void` | Appends an additional value to the named header without replacing existing values. |
| `delete` | `delete(name: string): void` | Removes the named header. |
| `has` | `has(name: string): boolean` | Returns `true` if the named header exists. |
| `entries` | `entries(): IterableIterator<[string, string]>` | Iterates over all `[name, value]` pairs. |
| `keys` | `keys(): IterableIterator<string>` | Iterates over all header names. |
| `values` | `values(): IterableIterator<string>` | Iterates over all header values. |
| `forEach` | `forEach(callback: (value, name, headers) => void): void` | Calls callback for each header entry. |

### Constraints

- Request and Response headers received from the runtime are **immutable**. Do not attempt to mutate `event.request.headers` directly.
- To produce modified headers, construct a new `Headers` object — either empty or initialized from an existing object — then call `set`, `append`, or `delete` on the new instance.
- Pass the new `Headers` instance to the `Response` constructor via the `headers` option.

## Environment Variables (fastedge::env)

### Import

```javascript
import { getEnv } from 'fastedge::env';
```

- `fastedge::env` is a **host-provided module**. It is NOT an npm package and must not be listed in `package.json` dependencies.

### API

```javascript
getEnv(name: string): string | null
```

- `name` — the name of the environment variable as configured in the Gcore dashboard or via the FastEdge API.
- Returns the string value, or `null` if the variable is not set.
- Use the nullish coalescing operator (`?? ''`) to provide a fallback: `getEnv('VAR') ?? ''`.

### Environment Variables Required

- `MY_CUSTOM_ENV_VAR` — any custom value to inject as a response header. Adapt the variable name to the actual use case.
- Variables are configured when creating or updating the app via the Gcore dashboard or API. They are not available at build time.

## Build Notes

- Build command: `fastedge-build src/index.js dist/headers.wasm`
- Defined in `package.json` scripts as `"build": "fastedge-build src/index.js dist/headers.wasm"`.
- `@gcoredev/fastedge-sdk-js` version constraint: `^2.3.0`.
- Package type must be `"module"` (ESM) in `package.json`.

## Source Material Reference

- `examples/headers/src/index.js`
- `examples/headers/package.json`

## Source Material

### FILE: examples/headers/src/index.js

```js
import { getEnv } from 'fastedge::env';

async function eventHandler(event) {
  const request = event.request;

  const customEnvVariable = getEnv('MY_CUSTOM_ENV_VAR') ?? '';

  const responseHeaders = new Headers(request.headers);
  responseHeaders.set('my-custom-header', customEnvVariable);

  return new Response('Returned all headers with a custom header added', {
    headers: responseHeaders,
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```


### FILE: examples/headers/package.json

```json
{
  "name": "fastedge-example-headers",
  "version": "1.0.0",
  "description": "FastEdge JS example: header manipulation with env vars",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/headers.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```
