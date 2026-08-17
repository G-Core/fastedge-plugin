<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: 81145a9a43ec499240c687bd49376ab20c72b11c
      updated: 2026-08-17
-->

---
type: feature
app_type: http
languages: [javascript]
capabilities: [secrets, rotation]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/secret-rotation
---

# Secret Rotation (HTTP, JavaScript)

Feature blueprint for slot-based secret retrieval and rotation in a FastEdge HTTP app.

## When to Use

Use this pattern when you need to rotate a signing key or API token without redeploying the app. Stage the next secret value at a future slot while the current slot continues to serve live traffic. Pin verification to a historical slot for in-flight requests that were signed under a previous key.

---

## API Reference

### `fastedge::secret` module

```js
import { getSecret, getSecretEffectiveAt } from 'fastedge::secret';
```

#### `getSecret(name)`

| Parameter | Type   | Description              |
|-----------|--------|--------------------------|
| `name`    | string | Secret name (key)        |

- **Returns**: `string | null` — current value of the named secret, or `null` if not set.
- Equivalent to `getSecretEffectiveAt(name, currentSlot)` where `currentSlot` is the latest slot stored for the secret.

#### `getSecretEffectiveAt(name, slot)`

| Parameter | Type   | Description                                                        |
|-----------|--------|--------------------------------------------------------------------|
| `name`    | string | Secret name (key)                                                  |
| `slot`    | number | Slot index or unix timestamp (non-negative integer)                |

- **Returns**: `string | null` — the value from the highest slot `<= slot`, or `null` if no slot satisfies the constraint.
- **Slot model**: slots are interpreted as either indices (`0, 1, 2, …`) or unix timestamps. The host resolves by returning the value stored at the highest slot number that is less than or equal to the supplied slot number.

---

## Slot Resolution Pattern

```js
// Read slot from request header; default to current unix timestamp.
// Slots can be indices (0, 1, 2…) or unix timestamps.
// Host returns the value from the highest slot <= this number.
const slotHeader = request.headers.get('x-slot');
const slot =
  slotHeader !== null ? Number.parseInt(slotHeader, 10) : Math.floor(Date.now() / 1000);

if (!Number.isFinite(slot) || slot < 0) {
  return new Response('x-slot header must be a non-negative integer', { status: 400 });
}
```

- Default slot: `Math.floor(Date.now() / 1000)` (current unix timestamp in seconds).
- Validation: reject with HTTP 400 if the parsed value is not a finite non-negative integer.

---

## Secret Name Override Pattern

```js
const secretName = request.headers.get('x-secret-name') ?? 'TOKEN_SECRET';
```

- Default secret name: `'TOKEN_SECRET'`.
- Override via `x-secret-name` request header.

---

## Full Implementation

```js
import { getSecret, getSecretEffectiveAt } from 'fastedge::secret';

function app(event) {
  const { request } = event;

  // Read the slot from the x-slot header, defaulting to the current unix timestamp.
  // Slots can be interpreted either as indices (0, 1, 2...) or as unix timestamps;
  // the host returns the value from the highest slot <= this number.
  const slotHeader = request.headers.get('x-slot');
  const slot =
    slotHeader !== null ? Number.parseInt(slotHeader, 10) : Math.floor(Date.now() / 1000);

  if (!Number.isFinite(slot) || slot < 0) {
    return new Response('x-slot header must be a non-negative integer', { status: 400 });
  }

  const secretName = request.headers.get('x-secret-name') ?? 'TOKEN_SECRET';

  const current = getSecret(secretName);
  const effective = getSecretEffectiveAt(secretName, slot);

  const body = JSON.stringify({
    secret_name: secretName,
    slot,
    current,
    effective_at_slot: effective,
    is_same: current === effective,
  });

  return new Response(body, {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(app(event));
});
```

---

## Response Shape

```json
{
  "secret_name": "TOKEN_SECRET",
  "slot": 1716201600,
  "current": "<current-secret-value>",
  "effective_at_slot": "<value-at-slot>",
  "is_same": true
}
```

| Field               | Type            | Description                                                      |
|---------------------|-----------------|------------------------------------------------------------------|
| `secret_name`       | string          | The resolved secret name used for lookup                         |
| `slot`              | number          | The slot number used for effective-at lookup                     |
| `current`           | string \| null  | Value from `getSecret` (latest slot)                             |
| `effective_at_slot` | string \| null  | Value from `getSecretEffectiveAt` at the requested slot          |
| `is_same`           | boolean         | Whether `current === effective_at_slot`                          |

This shape is the diagnostic surface for verifying that rotation is working correctly.

---

## Error Conditions

| Condition                                                     | Response                                                           |
|---------------------------------------------------------------|--------------------------------------------------------------------|
| `x-slot` present but not a valid non-negative integer         | `400 x-slot header must be a non-negative integer`                 |
| Secret name not found                                         | `current` and/or `effective_at_slot` fields are `null`             |

---

## Build Notes

**`package.json` build script:**

```json
{
  "scripts": {
    "build": "fastedge-build src/index.js dist/secret-rotation.wasm"
  }
}
```

- Entry point: `src/index.js`
- Output: `dist/secret-rotation.wasm`
- Build tool: `fastedge-build` (from `@gcoredev/fastedge-sdk-js`)

**Dependencies:**

```json
{
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.2.2"
  }
}
```

---

## Constraints

- `slot` must be a non-negative finite integer. Floats, `NaN`, `Infinity`, and negative values are invalid.
- `getSecretEffectiveAt` returns `null` if no slot exists that is `<=` the supplied value.
- `getSecret` and `getSecretEffectiveAt` are synchronous — no `await` required.
- Module specifier is `fastedge::secret` (double colon, not a scoped npm package).

---

## See Also

- fastedge-sdk-js SDK reference
- http-base skeleton
- deploy skill (for uploading secrets via the API before deploying)
- manage skill (`secrets` subcommand for secret CRUD operations)
