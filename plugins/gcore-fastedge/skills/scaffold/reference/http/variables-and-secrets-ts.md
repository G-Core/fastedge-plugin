<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: 81145a9a43ec499240c687bd49376ab20c72b11c
      updated: 2026-08-20
-->

---
type: feature
app_type: http
languages: [javascript]
capabilities: [env, secrets]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/variables-and-secrets
---

# Feature: Environment Variables and Secrets (JavaScript)

## Purpose

Parameterise a FastEdge worker with runtime configuration without baking values into the WASM binary. Use `getEnv` for non-sensitive configuration visible in the app config, and `getSecret` for sensitive credentials that operators upload but cannot read back through the API.

## Imports

```js
import { getEnv } from 'fastedge::env';
import { getSecret } from 'fastedge::secret';
```

Both imports must be present when the worker uses both APIs. They are separate modules with distinct trust models.

## API Reference

### `getEnv(name: string): string | null`

- **Module**: `fastedge::env`
- **Parameter**: `name` — the environment variable key, case-sensitive string
- **Returns**: `string` if the variable is set; `null` if not set
- **Constraint**: Must be called inside the fetch event handler (request-time). Do not call at module scope — values are per-request configuration, not static globals.
- **Trust model**: Environment variable values are visible in the app configuration via the FastEdge API and dashboard.

### `getSecret(name: string): string | null`

- **Module**: `fastedge::secret`
- **Parameter**: `name` — the secret key, case-sensitive string
- **Returns**: `string` if the secret is set; `null` if not set
- **Constraint**: Must be called inside the fetch event handler (request-time). Do not call at module scope.
- **Trust model**: Secrets are write-only. Operators upload secret values through the FastEdge API, but the values cannot be read back through the API or dashboard. The WASM worker is the only runtime consumer.

## Null Guard Pattern

Both APIs return `string | null`. Always apply a null-coalescing fallback before use in string contexts:

```js
const username = getEnv('USERNAME') ?? '';
const password = getSecret('PASSWORD') ?? '';
```

Do not inline `getEnv(...)` or `getSecret(...)` directly into template literals or string concatenation without a null guard — this produces the string `"null"` rather than an empty string or a handled absence.

## Complete Example

```js
import { getEnv } from 'fastedge::env';
import { getSecret } from 'fastedge::secret';

async function eventHandler(event) {
  // Both calls must be inside the handler — not at module scope
  const username = getEnv('USERNAME') ?? '';   // visible in app config
  const password = getSecret('PASSWORD') ?? ''; // write-only; not readable via API

  return new Response(`Username: ${username}, Password: ${password}`);
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```

## Build Configuration

**package.json** (relevant fields):

```json
{
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/variables-and-secrets.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```

- Entry point: `src/index.js`
- Output: `dist/variables-and-secrets.wasm`
- Build tool: `fastedge-build` (provided by `@gcoredev/fastedge-sdk-js`)

## When to Use

- Worker needs runtime configuration that differs between environments (staging vs. production) → use `getEnv`
- Worker needs credentials, tokens, or keys that must not be exposed in config or logs → use `getSecret`
- Neither value should be hardcoded in source or compiled into the WASM binary

## Constraints Summary

| Constraint | `getEnv` | `getSecret` |
|---|---|---|
| Call location | Inside fetch handler only | Inside fetch handler only |
| Return type | `string \| null` | `string \| null` |
| Null guard required | Yes | Yes |
| Visible in API/dashboard | Yes | No (write-only) |
| Readable by operator after upload | Yes | No |

## See Also

- http-base skeleton reference
- deploy skill (for setting env vars and uploading secrets via the FastEdge API)
- manage skill (for updating secrets on an existing app)
- platform-overview reference (for app configuration model)

## Source Material

### FILE: examples/variables-and-secrets/src/index.js

```js
import { getEnv } from 'fastedge::env';
import { getSecret } from 'fastedge::secret';

async function eventHandler(event) {
  const username = getEnv('USERNAME') ?? '';
  const password = getSecret('PASSWORD') ?? '';

  return new Response(`Username: ${username}, Password: ${password}`);
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```

### FILE: examples/variables-and-secrets/package.json

```json
{
  "name": "fastedge-example-variables-and-secrets",
  "version": "1.0.0",
  "description": "FastEdge JS example: environment variables and secrets",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/variables-and-secrets.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```
