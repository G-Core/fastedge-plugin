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
languages: [typescript, javascript]
capabilities: [geo-routing, geo-redirect]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/geo-redirect
---

# Feature: Geo-Based Redirect (HTTP JavaScript)

## When to Use

Use this blueprint when the user needs to redirect visitors to different origins based on their geographic location. Common use cases: country-specific content, regional CDN routing, localized landing pages, compliance-driven geo-fencing.

## Dependencies to Add

No additional npm dependencies beyond the base skeleton. Uses the `fastedge::env` host module for reading environment variables.

## Environment Variables Required

- `BASE_ORIGIN` — default redirect URL when no country-specific override exists (e.g., `https://example.com`)
- Per-country overrides using the ISO 3166-1 alpha-2 country code as the variable name (e.g., `DE` = `https://de.example.com`, `FR` = `https://fr.example.com`)

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
async function eventHandler({ request }) {
  const baseOrigin = getEnv('BASE_ORIGIN');

  if (!baseOrigin) {
    return new Response('BASE_ORIGIN environment variable is not set', {
      status: 500,
    });
  }

  const countryCode = request.headers.get('geoip-country-code');

  const customOrigin = countryCode ? getEnv(countryCode) : null;

  const redirectOrigin = customOrigin ?? baseOrigin;

  return Response.redirect(redirectOrigin, 302);
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```

## Geolocation Detection

- Client location is determined via the `geoip-country-code` request header.
- This header is automatically injected by the FastEdge platform based on the client's IP address.
- No configuration is required — the header is available on every inbound request.
- Value format: ISO 3166-1 alpha-2 country code string (e.g., `US`, `DE`, `FR`, `JP`).
- If the client's country cannot be determined, the header may be absent; `request.headers.get('geoip-country-code')` returns `null` in that case.

## Routing Logic

1. Read `BASE_ORIGIN` from environment — used as the fallback redirect target.
2. Read `geoip-country-code` from request headers.
3. If a country code is present, attempt to read a matching environment variable (e.g., `getEnv('DE')`).
4. If a country-specific variable exists, redirect to that URL; otherwise redirect to `BASE_ORIGIN`.
5. Redirect is issued as HTTP 302 using `Response.redirect(url, 302)`.

## API Used

### `getEnv(name: string): string | null`

- **Module**: `fastedge::env` (host-provided — not an npm package)
- **Parameter**: `name` — environment variable name (string)
- **Returns**: variable value as string, or `null` if not set
- **Usage**: `import { getEnv } from 'fastedge::env';`

### `request.headers.get(name: string): string | null`

- Standard Fetch API `Headers.get()` method.
- Returns the header value as a string, or `null` if the header is absent.

### `Response.redirect(url: string, status?: number): Response`

- Standard Web API available in the FastEdge runtime.
- `status` defaults to 302 when omitted; explicitly pass `302` for clarity.

## Build Notes

- Build command: `fastedge-build src/index.js dist/geo-redirect.wasm`
- `fastedge::env` is a host-provided module — do not install it via npm.
- `Response.redirect` is a standard Web API available in the FastEdge runtime.
- Environment variables are set in the Gcore dashboard or via the API when creating or updating the FastEdge app.
- Country-specific origins are configured as environment variables using ISO 3166-1 alpha-2 codes. If no matching variable exists, `BASE_ORIGIN` is used as the fallback.
- If `BASE_ORIGIN` is not set, the handler returns HTTP 500 with a descriptive error message.
- SDK dependency: `@gcoredev/fastedge-sdk-js` `^2.3.0` (as of source commit `81145a9a43ec499240c687bd49376ab20c72b11c`).

## Source Material

### FILE: examples/geo-redirect/src/index.js

```js
import { getEnv } from 'fastedge::env';

async function eventHandler({ request }) {
  const baseOrigin = getEnv('BASE_ORIGIN');

  if (!baseOrigin) {
    return new Response('BASE_ORIGIN environment variable is not set', {
      status: 500,
    });
  }

  const countryCode = request.headers.get('geoip-country-code');

  const customOrigin = countryCode ? getEnv(countryCode) : null;

  const redirectOrigin = customOrigin ?? baseOrigin;

  return Response.redirect(redirectOrigin, 302);
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```

### FILE: examples/geo-redirect/package.json

```json
{
  "name": "fastedge-example-geo-redirect",
  "version": "1.0.0",
  "description": "FastEdge JS example: geo-based redirect using env vars",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/geo-redirect.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```
