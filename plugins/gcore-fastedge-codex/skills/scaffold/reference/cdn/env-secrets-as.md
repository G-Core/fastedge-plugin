<!--
  auto-updated: true
  sources:
    - id: proxy-wasm-sdk-as
      ref: master
      commit: 8e3bb621bc013a0aed7e52122066b417ad62a207
      updated: 2026-08-20
-->

---
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [env-vars, secrets, config]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/variablesAndSecrets
---

# Environment Variables and Secrets — AssemblyScript (CDN)

## When to Use

Use this feature when a CDN app needs to read non-sensitive configuration values (environment variables) or platform-managed credentials (secrets) at request time — for example, forwarding a username or password to an upstream service.

## Imports

```typescript
import {
  getEnv,
  getSecret,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";
```

No additional dependencies beyond the base skeleton are required.

## API Reference

### `getEnv(name: string): string`

Reads an environment variable by name.

- **Parameter**: `name` — variable name as configured on the FastEdge application
- **Returns**: the variable value as a `string`; returns an empty string (`""`) if the variable is not set — never returns `null`
- **Use for**: non-sensitive configuration values

### `getSecret(name: string): string`

Reads a platform-managed secret by name.

- **Parameter**: `name` — secret name as configured on the FastEdge application
- **Returns**: the secret value as a `string`; returns an empty string (`""`) if the secret is not set — never returns `null`
- **Use for**: credentials and other sensitive values

### `getSecretEffectiveAt(name: string, slot: u32): string`

Rotation-aware variant of `getSecret`. Reads a secret value pinned to a specific rotation slot.

- **Parameters**:
  - `name` — secret name
  - `slot` — rotation slot index
- **Returns**: the secret value for the specified slot as a `string`

### `setLogLevel(level: LogLevelValues): void`

Sets the minimum log level for the context. Call once during `createContext`.

- Imported from `@gcoredev/proxy-wasm-sdk-as/assembly`

## Not-Found Check Pattern

Both `getEnv` and `getSecret` return an empty string when the value is absent. Check with `value.length === 0` or `value === ""`. Do NOT use `value == null` — the SDK never returns null.

```typescript
const username = getEnv("USERNAME");
if (username.length === 0) {
  // variable not configured
}
```

## Usage Pattern

```typescript
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy";
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
  getEnv,
  getSecret,
  setLogLevel,
} from "@gcoredev/proxy-wasm-sdk-as/assembly/fastedge";

class VariablesRoot extends RootContext {
  createContext(context_id: u32): Context {
    setLogLevel(LogLevelValues.info);
    return new VariablesContext(context_id, this);
  }
}

class VariablesContext extends Context {
  constructor(context_id: u32, root_context: VariablesRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    const username = getEnv("USERNAME");
    const password = getSecret("PASSWORD");

    // Log presence without exposing the secret value
    log(LogLevelValues.info, "USERNAME: " + username);
    log(LogLevelValues.info, "PASSWORD: [set, length " + password.length.toString() + "]");

    // Forward values as request headers to upstream
    stream_context.headers.request.add("x-env-username", username);
    stream_context.headers.request.add("x-env-password", password);

    return FilterHeadersStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => {
  return new VariablesRoot(context_id);
}, "variablesAndSecrets");
```

## Application Configuration

| Name       | Type                 | Description                            |
| ---------- | -------------------- | -------------------------------------- |
| `USERNAME` | Environment variable | The username value to forward upstream |
| `PASSWORD` | Secret               | The password value to forward upstream |

Configure both on the FastEdge application before deployment.

## Security Constraints

- **Never log secret values verbatim.** Logs are persisted and may be accessible to operators. Log only metadata such as value length, as shown in the example.
- **Limit header forwarding.** Only forward secret values as headers to upstream systems that require them. Avoid broadcasting credentials to systems that do not need them.

## Local Testing

The test runner maps environment variable names as follows:

| Env key                        | Maps to             |
| ------------------------------ | ------------------- |
| `FASTEDGE_VAR_ENV_<NAME>`      | `getEnv("NAME")`    |
| `FASTEDGE_VAR_SECRET_<NAME>`   | `getSecret("NAME")` |

Use `"dotenv": {"enabled": true}` in the test fixture to load values from a `.env` file (e.g. `fixtures/.env`):

```
FASTEDGE_VAR_ENV_USERNAME=my-username
FASTEDGE_VAR_SECRET_PASSWORD=my-password
```

## Build

```sh
pnpm install
pnpm run asbuild
```

| Output file                            | Description                                      |
| -------------------------------------- | ------------------------------------------------ |
| `build/variablesAndSecrets.wasm`       | Optimised release binary — upload to FastEdge    |
| `build/variablesAndSecrets-debug.wasm` | Debug binary with source maps                    |

Upload `build/variablesAndSecrets.wasm` to the FastEdge portal and attach it to your CDN application.

## See Also

- cdn-base skeleton (base request/response handling structure)
- fastedge-test reference (local WASM test runner and fixture format)
- platform-overview reference (FastEdge application configuration and secret management)
