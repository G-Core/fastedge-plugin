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
capabilities: [ab-testing]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/ab-testing
---

# Feature: A/B Testing (HTTP JavaScript)

## When to Use

Use this blueprint when the user needs cookie-based A/B testing at the edge. The app assigns visitors to test variants using a persistent cookie, forwards variant headers to the origin, and hides the A/B cookie from the downstream service. Common use cases: split testing UI variants, weighted feature rollouts, multivariate experiments, serving different content based on assignment.

## Dependencies to Add

No additional npm dependencies beyond the base skeleton. Uses the `fastedge::env` host module for reading the outbound URL.

```json
{
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```

## Environment Variables Required

| Variable | Type | Required | Description |
|---|---|---|---|
| `OUTBOUND_URL` | string | yes | URL of the outbound/origin service to proxy requests to (e.g., `https://your-origin.example.com/`) |

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
const testConfig = {
  logo: [
    { variant: 'hops', weight: 50 },
    { variant: 'bottle', weight: 50 },
  ],
  font: [
    { variant: 'exo2', weight: 40 },
    { variant: 'gloria', weight: 65 },
    { variant: 'standard', weight: 45 },
  ],
};

async function eventHandler({ request }) {
  const [xid, slicedHeaders] = sliceAbTestIdFromCookie(request);

  const headers = createAbTestHeaders(slicedHeaders, testConfig, xid);

  const outboundUrl = getEnv('OUTBOUND_URL');
  if (!outboundUrl || !String(outboundUrl).trim()) {
    return new Response('OUTBOUND_URL environment variable is not configured', {
      status: 500,
    });
  }

  const response = await fetch(outboundUrl, { headers });

  // Request/Response Headers are immutable, so we need to create a new Headers object
  const resHeaders = new Headers(response.headers);
  resHeaders.set(
    'set-cookie',
    `x-fastedge-abid=${xid}; Max-Age=31536000; Path=/; Secure; HttpOnly; SameSite=Lax;`,
  );

  return new Response(response.body, {
    status: response.status,
    headers: resHeaders,
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});

const sliceAbTestIdFromCookie = ({ headers: reqHeaders }) => {
  // Request/Response Headers are immutable, so we need to create a new Headers object
  const headers = new Headers(reqHeaders);
  const cookie = headers.get('cookie') || '';
  // Read the existing `xid` cookie value.
  const xid = (cookie.match(/(?:^|;) *x-fastedge-abid=((0|1|)\.\d+) *(?:;|$)/u) || [])[1];
  if (xid) {
    // Request contains A/B cookie, hide it from the origin
    const newCookie = cookie.replace(/x-fastedge-abid=[^;]+;?\s*/gu, '');
    if (newCookie) {
      headers.set('cookie', newCookie);
    } else {
      headers.delete('cookie');
    }
    return [xid, headers];
  }
  const randomXid = `${Math.random()}`.slice(1, 5);
  // Request does not contain A/B cookie, return random number
  return [randomXid, headers];
};

const forceWeightsToPercentages = (testValues) => {
  const total = testValues.reduce((acc, { weight }) => acc + weight, 0);
  return testValues.map(({ variant, weight }) => ({
    variant,
    percentage: (weight / total) * 100,
  }));
};

const createAbTestHeaders = (reqHeaders, testConfig, xid) => {
  const headers = new Headers(reqHeaders);
  for (const testName of Object.keys(testConfig)) {
    const xidPercentage = Number.parseFloat(xid) * 100;
    const testValues = forceWeightsToPercentages(testConfig[testName]);
    let start = 0;
    for (const { variant, percentage } of testValues) {
      const end = start + percentage;
      if (xidPercentage >= start && xidPercentage < end) {
        headers.set(`ab-test-${testName}`, variant);
        break;
      }
      start = end;
    }
  }
  return headers;
};
```

## Key Logic: Variant Assignment

### Cookie-based assignment flow

1. Incoming request is checked for an existing `x-fastedge-abid` cookie.
2. **Cookie present**: Extract the `xid` value; strip the cookie from the forwarded request headers (origin remains unaware of the testing mechanism).
3. **Cookie absent**: Generate a random `xid` using `` `${Math.random()}`.slice(1, 5) `` — produces a string like `.734` representing a value in `[0, 1)`.
4. The `xid` is used consistently across all test dimensions in `testConfig` to assign the same visitor to deterministic variants per request.
5. The `x-fastedge-abid` cookie is set on the response with a 1-year `Max-Age`, persisting the assignment across future requests.

### Cookie format

```
x-fastedge-abid=<xid>; Max-Age=31536000; Path=/; Secure; HttpOnly; SameSite=Lax;
```

- `<xid>`: decimal string matching pattern `(0|1|)\.\d+` (e.g., `.734`, `0.734`, `1.0`)
- `Max-Age=31536000`: 1-year persistence
- `Secure; HttpOnly; SameSite=Lax`: production-safe defaults

### Variant selection algorithm (`createAbTestHeaders`)

For each test in `testConfig`:
1. Normalize weights to percentages via `forceWeightsToPercentages` (weights need not sum to 100).
2. Map `xid` to a percentage: `xidPercentage = parseFloat(xid) * 100`.
3. Walk variants in order; assign the first variant whose cumulative range `[start, end)` contains `xidPercentage`.
4. Set request header `ab-test-<testName>: <variant>` for the matched variant.

### `testConfig` structure

```javascript
const testConfig = {
  <testName>: [
    { variant: '<variantId>', weight: <number> },
    // ...
  ],
  // additional tests...
};
```

- `testName`: string — becomes the header name suffix (`ab-test-<testName>`)
- `variant`: string — the value set on the header
- `weight`: number — relative weight; normalized at runtime; does not need to sum to 100
- `testConfig` is defined at module scope — shared across all requests

## Internal API Signatures

### `sliceAbTestIdFromCookie(request)`

```
Input:  request: Request
Output: [xid: string, headers: Headers]
```

- Reads `x-fastedge-abid` cookie from `request.headers`.
- If found: strips cookie from a new `Headers` copy; returns `[existingXid, modifiedHeaders]`.
- If not found: generates `randomXid = Math.random().toString().slice(1, 5)`; returns `[randomXid, newHeaders]`.
- Cookie regex pattern: `/(?:^|;) *x-fastedge-abid=((0|1|)\.\d+) *(?:;|$)/u`
- Cookie strip pattern: `/x-fastedge-abid=[^;]+;?\s*/gu`

### `forceWeightsToPercentages(testValues)`

```
Input:  testValues: Array<{ variant: string, weight: number }>
Output: Array<{ variant: string, percentage: number }>
```

- Sums all weights; maps each to `(weight / total) * 100`.
- Weights of zero result in 0% allocation.

### `createAbTestHeaders(reqHeaders, testConfig, xid)`

```
Input:  reqHeaders: Headers
        testConfig: Record<string, Array<{ variant: string, weight: number }>>
        xid: string
Output: Headers
```

- Returns a new `Headers` object with `ab-test-<testName>` headers set per variant assignment.
- Uses cumulative bucket range `[start, end)` for selection; first matching variant wins.
- Does not mutate `reqHeaders`; constructs a new `Headers` instance.

## Error Conditions

| Condition | Response |
|---|---|
| `OUTBOUND_URL` unset or blank | `500 OUTBOUND_URL environment variable is not configured` |
| Outbound fetch failure | Propagates fetch error (unhandled — caller receives rejected promise) |

## Build Notes

- Build command: `fastedge-build src/index.js dist/ab-testing.wasm`
- Plain JS — no TypeScript config needed.
- `fastedge::env` is a host-provided module, NOT an npm package. Do not add it to `package.json`.
- `Request` and `Response` headers are immutable in the FastEdge runtime. Always construct a new `Headers` object before modifying.
- `testConfig` is defined at module scope — shared across all requests. Variant weights are normalized per-request.
- The `x-fastedge-abid` cookie is stripped from forwarded request headers; the origin never sees it.

## See Also

- fastedge-sdk-js SDK reference
- http-base skeleton
- FastEdge build CLI reference

## Source Material

### FILE: examples/ab-testing/src/index.js

```js
import { getEnv } from 'fastedge::env';

const testConfig = {
  logo: [
    { variant: 'hops', weight: 50 },
    { variant: 'bottle', weight: 50 },
  ],
  font: [
    { variant: 'exo2', weight: 40 },
    { variant: 'gloria', weight: 65 },
    { variant: 'standard', weight: 45 },
  ],
};

async function eventHandler({ request }) {
  const [xid, slicedHeaders] = sliceAbTestIdFromCookie(request);

  const headers = createAbTestHeaders(slicedHeaders, testConfig, xid);

  // This is the URL of the outbound service - i.e. could be a url to your origin
  // e.g. https://template-invoice-ab-test-123456.fastedge.cdn.gc.onl/
  const outboundUrl = getEnv('OUTBOUND_URL');
  if (!outboundUrl || !String(outboundUrl).trim()) {
    return new Response('OUTBOUND_URL environment variable is not configured', {
      status: 500,
    });
  }

  const response = await fetch(outboundUrl, { headers });

  // Request/Response Headers are immutable, so we need to create a new Headers object
  const resHeaders = new Headers(response.headers);
  resHeaders.set(
    'set-cookie',
    `x-fastedge-abid=${xid}; Max-Age=31536000; Path=/; Secure; HttpOnly; SameSite=Lax;`,
  );

  return new Response(response.body, {
    status: response.status,
    headers: resHeaders,
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});

const sliceAbTestIdFromCookie = ({ headers: reqHeaders }) => {
  // Request/Response Headers are immutable, so we need to create a new Headers object
  const headers = new Headers(reqHeaders);
  const cookie = headers.get('cookie') || '';
  // Read the existing `xid` cookie value.
  const xid = (cookie.match(/(?:^|;) *x-fastedge-abid=((0|1|)\.\d+) *(?:;|$)/u) || [])[1];
  if (xid) {
    // Request contains A/B cookie, hide it from the origin
    const newCookie = cookie.replace(/x-fastedge-abid=[^;]+;?\s*/gu, '');
    if (newCookie) {
      headers.set('cookie', newCookie);
    } else {
      headers.delete('cookie');
    }
    return [xid, headers];
  }
  const randomXid = `${Math.random()}`.slice(1, 5);
  // Request does not contain A/B cookie, return random number
  return [randomXid, headers];
};

const forceWeightsToPercentages = (testValues) => {
  const total = testValues.reduce((acc, { weight }) => acc + weight, 0);
  return testValues.map(({ variant, weight }) => ({
    variant,
    percentage: (weight / total) * 100,
  }));
};

const createAbTestHeaders = (reqHeaders, testConfig, xid) => {
  const headers = new Headers(reqHeaders);
  for (const testName of Object.keys(testConfig)) {
    const xidPercentage = Number.parseFloat(xid) * 100;
    const testValues = forceWeightsToPercentages(testConfig[testName]);
    let start = 0;
    for (const { variant, percentage } of testValues) {
      const end = start + percentage;
      if (xidPercentage >= start && xidPercentage < end) {
        headers.set(`ab-test-${testName}`, variant);
        break;
      }
      start = end;
    }
  }
  return headers;
};
```


### FILE: examples/ab-testing/package.json

```json
{
  "name": "fastedge-example-ab-testing",
  "version": "1.0.0",
  "description": "FastEdge JS example: cookie-based A/B testing",
  "type": "module",
  "main": "src/index.js",
  "scripts": {
    "build": "fastedge-build src/index.js dist/ab-testing.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```
