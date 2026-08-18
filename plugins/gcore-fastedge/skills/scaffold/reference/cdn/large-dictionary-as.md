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
capabilities: [dictionary, large-config]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/largeDictionary
---

# Large Dictionary (AssemblyScript)

Read environment variables that exceed the 64 KB WASI size limit using the proxy-wasm dictionary API.

## When to Use

Use this feature when a CDN app needs to read configuration env values (e.g. large JSON blobs, PEM certificates, policy documents) that exceed the 64 KB WASI environment-variable limit. For all other env var access, prefer `getEnv`.

## API

### `getDictionary(name: string): string`

- **Import**: `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`
- **Parameter**: `name` — environment variable name
- **Returns**: variable value as `string`; returns empty string (`""`) if the variable is not set — never `null`
- **Mechanism**: calls `proxy_dictionary_get` internally, bypassing the WASI env var size limit
- **Constraint**: no upper size limit documented; use for values exceeding 64 KB

### `getEnv(name: string): string`

- **Import**: `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`
- **Use when**: value is under 64 KB — lower overhead than `getDictionary`

### Comparison

| Function | Use when |
|---|---|
| `getEnv(name)` | Value is under 64 KB (most cases) |
| `getDictionary(name)` | Value may exceed the 64 KB WASI limit |

## Minimal Implementation

```typescript
import {
  Context,
  FilterHeadersStatusValues,
  log,
  LogLevelValues,
  registerRootContext,
  RootContext,
  stream_context,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";
import {
  getDictionary,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

class LargeDictionaryRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new LargeDictionaryContext(context_id, this);
  }
}

class LargeDictionaryContext extends Context {
  constructor(context_id: u32, root_context: LargeDictionaryRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    // Use getDictionary for environment variables that may exceed 64KB.
    // For normal-sized env vars (< 64KB), use getEnv instead.
    const config = getDictionary("LARGE_CONFIG");

    const size = config.length;
    log(LogLevelValues.info, "LARGE_CONFIG size: " + size.toString() + " bytes");

    stream_context.headers.request.add("x-config-size", size.toString());

    return FilterHeadersStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => {
  return new LargeDictionaryRoot(context_id);
}, "largeDictionary");
```

## Environment Variables

| Name | Type | Description |
|---|---|---|
| `LARGE_CONFIG` | Environment variable | Large configuration payload (e.g. JSON, PEM certificate). Read via `getDictionary`. |

## Build

```sh
pnpm install
pnpm run asbuild
```

| Output file | Description |
|---|---|
| `build/largeDictionary.wasm` | Optimised release binary — upload to FastEdge |
| `build/largeDictionary-debug.wasm` | Debug binary with source maps |

Build scripts defined in `package.json`:
- `asbuild:debug` — compiles with debug target
- `asbuild:release` — compiles with release target
- `asbuild` — runs both

## Dependencies

| Package | Role |
|---|---|
| `@gcoredev/proxy-wasm-sdk-as` | Proxy-wasm SDK for AssemblyScript (^1.2.3) |
| `assemblyscript` | AssemblyScript compiler (devDependency, ^0.28.9) |
| `@assemblyscript/wasi-shim` | WASI shim (devDependency, ^0.1.0) |

No additional dependencies beyond the cdn-base skeleton.

## Key Constraints

- `getDictionary` returns `""` (empty string) when the variable is absent — always check `config.length === 0` rather than a null check
- All dictionary read logic belongs in `onRequestHeaders`
- The 64 KB limit applies to the WASI environment-variable interface; `getDictionary` uses `proxy_dictionary_get` and is not subject to this limit

## See Also

- cdn-base skeleton reference
- proxy-wasm-sdk-as SDK reference (AssemblyScript)
- platform-overview reference for environment variable configuration
