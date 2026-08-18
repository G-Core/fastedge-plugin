<!--
  auto-updated: true
  sources:
    - id: proxy-wasm-sdk-as
      ref: master
      commit: 8e3bb621bc013a0aed7e52122066b417ad62a207
      updated: 2026-08-17
-->

---
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [geo-blocking]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/geoBlock
---

# Geo Block — AssemblyScript (CDN Feature Blueprint)

Blocks incoming requests based on the client's country code. Use this blueprint when the user wants to restrict or block access based on geographic location.

---

## When to Use

- User wants to block requests from specific countries
- User wants country-based access control at the edge
- User needs geographic restriction using ISO 3166-1 alpha-2 country codes

---

## Imports

```typescript
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
import {
  Context,
  FilterHeadersStatusValues,
  get_property,
  log,
  LogLevelValues,
  registerRootContext,
  RootContext,
  send_http_response,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import {
  getEnv,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
```

---

## Environment Variables

| Variable    | Required | Example    | Description                                                       |
| ----------- | -------- | ---------- | ----------------------------------------------------------------- |
| `BLACKLIST` | Yes      | `RU,CN,KP` | Comma-separated list of ISO 3166-1 alpha-2 country codes to block |

---

## Runtime Properties

| Property          | Source               | Description                                     |
| ----------------- | -------------------- | ----------------------------------------------- |
| `request.country` | FastEdge Geo-IP data | Two-letter country code of the incoming request |

Accessed via: `get_property("request.country")` — returns `ArrayBuffer`; zero `byteLength` indicates country is unavailable.

Country code matching is exact-match and case-sensitive. FastEdge always provides uppercase ISO 3166-1 alpha-2 codes (e.g. `CN`, `RU`). Ensure `BLACKLIST` values use uppercase accordingly.

---

## Core Implementation Pattern

### Class Structure

```typescript
class GeoBlockRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new GeoBlock(context_id, this);
  }
}

class GeoBlock extends Context {
  constructor(context_id: u32, root_context: GeoBlockRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    // 1. Read BLACKLIST env var
    const blacklist = getEnv("BLACKLIST");
    if (!blacklist) {
      send_http_response(
        INTERNAL_SERVER_ERROR,
        "internal server error",
        String.UTF8.encode("App misconfigured"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    // 2. Parse comma-separated country codes
    const blacklistedCountries = blacklist
      .split(",")
      .map<string>((c) => c.trim());

    if (blacklistedCountries.length === 0) {
      send_http_response(
        INTERNAL_SERVER_ERROR,
        "internal server error",
        String.UTF8.encode("App misconfigured"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    // 3. Read client country from runtime property
    const country = get_property("request.country");
    if (country.byteLength === 0) {
      send_http_response(
        BAD_GATEWAY,
        "internal server error",
        String.UTF8.encode("Missing country information"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    // 4. Block if country is in blacklist
    const countryStr = String.UTF8.decode(country);
    if (blacklistedCountries.includes(countryStr)) {
      log(LogLevelValues.info, "geoBlock: blocked request from " + countryStr);
      send_http_response(
        FORBIDDEN,
        "forbidden",
        String.UTF8.encode("Request blacklisted"),
        [],
      );
      return FilterHeadersStatusValues.StopIteration;
    }

    log(LogLevelValues.info, "geoBlock: allowed request from " + countryStr);
    return FilterHeadersStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => {
  return new GeoBlockRoot(context_id);
}, "geoBlock");
```

---

## Logging

Both blocked and allowed requests are logged at `INFO` level, providing an audit trail for all traffic decisions.

| Event            | Log message                                      |
| ---------------- | ------------------------------------------------ |
| Request blocked  | `"geoBlock: blocked request from " + countryStr` |
| Request allowed  | `"geoBlock: allowed request from " + countryStr` |

Log level is set via `setLogLevel(LogLevelValues.info)` inside `createContext`.

---

## Status Codes Used

| Constant                | Value | Condition                                              |
| ----------------------- | ----- | ------------------------------------------------------ |
| `FORBIDDEN`             | 403   | Request's country code is in the blacklist             |
| `BAD_GATEWAY`           | 502   | `request.country` property is empty/unavailable        |
| `INTERNAL_SERVER_ERROR` | 500   | `BLACKLIST` env var is missing or parses to empty list |

---

## `send_http_response` Signature

```typescript
send_http_response(
  status_code: u32,
  status_message: string,
  body: ArrayBuffer,
  headers: Array<[string, string]>
): void
```

---

## `getEnv` Signature

```typescript
getEnv(name: string): string | null
```

- Returns `null` if the environment variable is not set.
- Imported from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`.

---

## `setLogLevel` Signature

```typescript
setLogLevel(level: LogLevelValues): void
```

- Imported from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`.
- Call inside `createContext` to configure log verbosity for the context lifetime.

---

## `get_property` Usage

```typescript
const country = get_property("request.country"); // returns ArrayBuffer
const countryStr = String.UTF8.decode(country);   // decode to string, e.g. "RU"
```

- Returns an `ArrayBuffer`; check `byteLength === 0` before decoding.

---

## String Parsing Pattern (Comma-Separated List)

```typescript
const blacklistedCountries = blacklist
  .split(",")
  .map<string>((c) => c.trim());
```

Trims whitespace from each entry. Validate that `length > 0` after parsing.

---

## Build

```sh
pnpm install
pnpm run asbuild
```

| Output File                 | Description                          |
| --------------------------- | ------------------------------------ |
| `build/geoBlock.wasm`       | Release binary — upload to FastEdge  |
| `build/geoBlock-debug.wasm` | Debug binary with source maps        |

Build scripts defined in `package.json`:
- `asbuild:debug` — `asc assembly/index.ts --target debug`
- `asbuild:release` — `asc assembly/index.ts --target release`
- `asbuild` — runs both debug and release

---

## Dependencies

| Package                       | Role                                   |
| ----------------------------- | -------------------------------------- |
| `@gcoredev/proxy-wasm-sdk-as` | Core proxy-wasm SDK for AssemblyScript |
| `@assemblyscript/wasi-shim`   | WASI compatibility shim (dev)          |
| `assemblyscript`              | AssemblyScript compiler (dev)          |

---

## Error Conditions

| Condition                                    | Response                                             | Status |
| -------------------------------------------- | ---------------------------------------------------- | ------ |
| `BLACKLIST` env var not set                  | `StopIteration`, body: "App misconfigured"           | 500    |
| `BLACKLIST` parses to empty list             | `StopIteration`, body: "App misconfigured"           | 500    |
| `request.country` property empty/unavailable | `StopIteration`, body: "Missing country information" | 502    |
| Country code found in blacklist              | `StopIteration`, body: "Request blacklisted"         | 403    |
| Country code not in blacklist                | `Continue`                                           | —      |

---

## See Also

- proxy-wasm-sdk-as SDK reference (AssemblyScript)
- cdn-base skeleton blueprint
- Platform overview (request properties, Geo-IP)
- FastEdge deploy reference
