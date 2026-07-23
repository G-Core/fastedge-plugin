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
capabilities: [kv-store]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/kv-store
---

# Feature: KV Store (HTTP TypeScript/JavaScript)

## When to Use

Use this blueprint when the user needs to read from or write to a key-value store at the edge. Common use cases: caching, session storage, feature flags, configuration data, bloom filter checks, sorted set queries.

## Dependencies to Add

No additional npm dependencies beyond the base skeleton. The KV Store API is provided by the `fastedge::kv` host module (built into the FastEdge runtime).

```json
{
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```

## Files to Create

### src/utils.ts

```typescript
const ALL_ACTIONS = ['get', 'scan', 'zscan', 'zrange', 'bfExists'] as const;

export type Action = (typeof ALL_ACTIONS)[number];

type ParamKey = 'action' | 'store' | 'key' | 'match' | 'min' | 'max' | 'item' | 'error';

type Params = { [key in ParamKey]: string };

export function validateQueryParams(queryParams: URLSearchParams): Params {
  const validParams = {} as Params;

  // Validate 'action' parameter
  const action = queryParams.get('action') ?? 'get';
  if (ALL_ACTIONS.includes(action as Action)) {
    validParams.action = action;
  } else {
    validParams.error = `Invalid action '${action}'. Supported actions are: ${ALL_ACTIONS.join(
      ', ',
    )}`;
    return validParams;
  }

  const requiredParameters = {
    store: [...ALL_ACTIONS],
    key: ['get', 'zrange', 'zscan', 'bfExists'],
    match: ['scan', 'zscan'],
    min: ['zrange'],
    max: ['zrange'],
    item: ['bfExists'],
  } as Record<ParamKey, Array<string>>;

  for (const [key, actions] of Object.entries(requiredParameters)) {
    if (actions.includes(action)) {
      const value = queryParams.get(key);
      if (value && value !== '') {
        validParams[key as ParamKey] = value;
      } else {
        validParams.error = `Query parameters must provide '${key}' for a '${action}' action.`;
        return validParams;
      }
    }
  }

  return validParams;
}

export const decodeValueArray = (arrVal: ArrayBuffer | null) => {
  if (arrVal) {
    const decoder = new TextDecoder();
    return decoder.decode(arrVal);
  }
  return '';
};

export const stringifyValueScoreTuples = (tupleList: Array<[ArrayBuffer, number]>): string => {
  let strResponse = '[';
  for (const tuple of tupleList) {
    strResponse += `{ Value: ${decodeValueArray(tuple[0])}, Score: ${tuple[1]} }, `;
  }
  strResponse += ']';
  return strResponse;
};
```

### .fastedge/build-config.js

```javascript
const config = {
  type: "http",
  tsConfigPath: "./tsconfig.json",
  entryPoint: "src/index.ts",
  wasmOutput: "dist/kv-store.wasm",
};

const serverConfig = {
  type: "http",
};

export { config, serverConfig };
```

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2023",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "lib": ["ES2023"],
    "types": ["@gcoredev/fastedge-sdk-js"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
```

## Files to Modify

### src/index.ts

**Add imports:**

```typescript
import { KvStore } from 'fastedge::kv';

import { Action, decodeValueArray, stringifyValueScoreTuples, validateQueryParams } from './utils';
```

**Replace handler body with:**

```typescript
async function eventHandler(event: FetchEvent): Promise<Response> {
  try {
    const { request: req } = event;
    const url = new URL(req.url);

    const params = validateQueryParams(url.searchParams);
    if (params.error) {
      throw new Error(params.error);
    }

    const myStore = KvStore.open(params.store);
    const action = params.action as Action;

    const responseObj: Record<string, string> = {
      Store: params.store,
      Action: action,
    };

    switch (action) {
      case 'get': {
        const response = myStore.get(params.key);
        responseObj.Key = params.key;
        responseObj.Response = decodeValueArray(response);
        break;
      }
      case 'scan': {
        const response = myStore.scan(params.match);
        responseObj.Match = params.match;
        responseObj.Response = response.join(', ');
        break;
      }
      case 'zrange': {
        const { key, min, max } = params;
        const response = myStore.zrangeByScore(key, Number.parseFloat(min), Number.parseFloat(max));
        responseObj.Key = key;
        responseObj.Min = min;
        responseObj.Max = max;
        responseObj.Response = stringifyValueScoreTuples(response);
        break;
      }
      case 'zscan': {
        const { key, match } = params;
        const response = myStore.zscan(key, match);
        responseObj.Key = key;
        responseObj.Match = match;
        responseObj.Response = stringifyValueScoreTuples(response);
        break;
      }
      case 'bfExists': {
        const { key, item } = params;
        const exists = myStore.bfExists(key, item);
        responseObj.Key = key;
        responseObj.Item = item;
        responseObj.Response = exists ? 'true' : 'false';
        break;
      }
      default:
        break;
    }

    return Response.json(responseObj);
  } catch (error: Error | unknown) {
    return Response.json({ error: `${(error as Error).message}` }, { status: 500 });
  }
}

addEventListener('fetch', (event: FetchEvent) => {
  event.respondWith(eventHandler(event));
});
```

## KV Store API Reference

### Import

```typescript
import { KvStore } from 'fastedge::kv';
```

`fastedge::kv` is a host-provided module. It is NOT an npm package. It is available at runtime in the FastEdge WASM environment only.

### KvStore.open(name: string): KvStore

Opens a named KV store. The store must be pre-created in the Gcore dashboard or API before the app can reference it.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Name of the KV store to open |

Returns: `KvStore` instance.

### Instance Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `get` | `get(key: string): ArrayBuffer \| null` | Returns value for `key`, or `null` if not found |
| `scan` | `scan(match: string): string[]` | Returns keys matching the glob pattern `match` |
| `zrangeByScore` | `zrangeByScore(key: string, min: number, max: number): Array<[ArrayBuffer, number]>` | Returns value-score tuples from sorted set `key` within score range `[min, max]` |
| `zscan` | `zscan(key: string, match: string): Array<[ArrayBuffer, number]>` | Returns value-score tuples from sorted set `key` where value matches pattern `match` |
| `bfExists` | `bfExists(key: string, item: string): boolean` | Returns `true` if `item` exists in bloom filter at `key` |

**Notes:**
- All KV Store operations are synchronous — no `await` needed.
- `get` returns `ArrayBuffer | null`. Use `TextDecoder` to convert to string.
- `scan` returns `string[]` (array of matching key names).
- `zrangeByScore` and `zscan` return `Array<[ArrayBuffer, number]>` — tuples of (value as ArrayBuffer, score as number).

### Query Parameter Contract (example app)

The example app routes all KV operations via URL query parameters:

| Parameter | Required for | Type | Description |
|-----------|-------------|------|-------------|
| `action` | all | `'get' \| 'scan' \| 'zscan' \| 'zrange' \| 'bfExists'` | Operation to perform. Defaults to `'get'` if omitted |
| `store` | all | `string` | Name of the KV store to open |
| `key` | `get`, `zrange`, `zscan`, `bfExists` | `string` | Key to operate on |
| `match` | `scan`, `zscan` | `string` | Glob pattern for key/value matching |
| `min` | `zrange` | `string` (parsed as float) | Minimum score bound |
| `max` | `zrange` | `string` (parsed as float) | Maximum score bound |
| `item` | `bfExists` | `string` | Item to check in bloom filter |

Missing required parameters return HTTP 500 with JSON `{ "error": "..." }`.

## Build Notes

- Build command: `fastedge-build -c` (the `-c` flag enables the custom build config from `.fastedge/build-config.js`).
- `build-config.js` sets `entryPoint: "src/index.ts"` and `wasmOutput: "dist/kv-store.wasm"`.
- The `fastedge::kv` import is a host-provided module — it is NOT an npm package. Do not attempt to install it via npm.
- KV Store operations are synchronous (no `await` needed) despite being host calls.
- The KV store must be pre-created in the Gcore dashboard or API before the app can use it. The store name is passed at runtime (e.g., as a query parameter).
- Available KV operations: `get`, `scan`, `zrangeByScore`, `zscan`, `bfExists`.
- `tsconfig.json` uses `"moduleResolution": "Bundler"` and `"target": "ES2023"`. Do not use `"moduleResolution": "Node"` or older ES targets with this SDK version.

## Source Material

### FILE: examples/kv-store/src/index.ts

```ts
import { KvStore } from 'fastedge::kv';

import { Action, decodeValueArray, stringifyValueScoreTuples, validateQueryParams } from './utils';

async function eventHandler(event: FetchEvent): Promise<Response> {
  try {
    const { request: req } = event;
    const url = new URL(req.url);

    const params = validateQueryParams(url.searchParams);
    if (params.error) {
      throw new Error(params.error);
    }

    const myStore = KvStore.open(params.store);
    const action = params.action as Action;

    const responseObj: Record<string, string> = {
      Store: params.store,
      Action: action,
    };

    switch (action) {
      case 'get': {
        const response = myStore.get(params.key);
        responseObj.Key = params.key;
        responseObj.Response = decodeValueArray(response);
        break;
      }
      case 'scan': {
        const response = myStore.scan(params.match);
        responseObj.Match = params.match;
        responseObj.Response = response.join(', ');
        break;
      }
      case 'zrange': {
        const { key, min, max } = params;
        const response = myStore.zrangeByScore(key, Number.parseFloat(min), Number.parseFloat(max));
        responseObj.Key = key;
        responseObj.Min = min;
        responseObj.Max = max;
        responseObj.Response = stringifyValueScoreTuples(response);
        break;
      }
      case 'zscan': {
        const { key, match } = params;
        const response = myStore.zscan(key, match);
        responseObj.Key = key;
        responseObj.Match = match;
        responseObj.Response = stringifyValueScoreTuples(response);
        break;
      }
      case 'bfExists': {
        const { key, item } = params;
        const exists = myStore.bfExists(key, item);
        responseObj.Key = key;
        responseObj.Item = item;
        responseObj.Response = exists ? 'true' : 'false';
        break;
      }
      default:
        break;
    }

    return Response.json(responseObj);
  } catch (error: Error | unknown) {
    return Response.json({ error: `${(error as Error).message}` }, { status: 500 });
  }
}

addEventListener('fetch', (event: FetchEvent) => {
  event.respondWith(eventHandler(event));
});
```

### FILE: examples/kv-store/src/utils.ts

```ts
const ALL_ACTIONS = ['get', 'scan', 'zscan', 'zrange', 'bfExists'] as const;

export type Action = (typeof ALL_ACTIONS)[number];

type ParamKey = 'action' | 'store' | 'key' | 'match' | 'min' | 'max' | 'item' | 'error';

type Params = { [key in ParamKey]: string };

export function validateQueryParams(queryParams: URLSearchParams): Params {
  const validParams = {} as Params;

  // Validate 'action' parameter
  const action = queryParams.get('action') ?? 'get';
  if (ALL_ACTIONS.includes(action as Action)) {
    validParams.action = action;
  } else {
    validParams.error = `Invalid action '${action}'. Supported actions are: ${ALL_ACTIONS.join(
      ', ',
    )}`;
    return validParams;
  }

  const requiredParameters = {
    store: [...ALL_ACTIONS],
    key: ['get', 'zrange', 'zscan', 'bfExists'],
    match: ['scan', 'zscan'],
    min: ['zrange'],
    max: ['zrange'],
    item: ['bfExists'],
  } as Record<ParamKey, Array<string>>;

  for (const [key, actions] of Object.entries(requiredParameters)) {
    if (actions.includes(action)) {
      const value = queryParams.get(key);
      if (value && value !== '') {
        validParams[key as ParamKey] = value;
      } else {
        validParams.error = `Query parameters must provide '${key}' for a '${action}' action.`;
        return validParams;
      }
    }
  }

  return validParams;
}

export const decodeValueArray = (arrVal: ArrayBuffer | null) => {
  if (arrVal) {
    const decoder = new TextDecoder();
    return decoder.decode(arrVal);
  }
  return '';
};

export const stringifyValueScoreTuples = (tupleList: Array<[ArrayBuffer, number]>): string => {
  let strResponse = '[';
  for (const tuple of tupleList) {
    strResponse += `{ Value: ${decodeValueArray(tuple[0])}, Score: ${tuple[1]} }, `;
  }
  strResponse += ']';
  return strResponse;
};
```

### FILE: examples/kv-store/package.json

```json
{
  "name": "fastedge-example-kv-store",
  "version": "1.0.0",
  "description": "FastEdge JS example: KV Store operations via query params",
  "type": "module",
  "scripts": {
    "build": "fastedge-build -c"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```

### FILE: examples/kv-store/tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2023",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "lib": ["ES2023"],
    "types": ["@gcoredev/fastedge-sdk-js"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
```
