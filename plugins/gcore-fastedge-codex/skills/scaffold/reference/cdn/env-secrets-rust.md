<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-08-20
-->

---
type: feature
app_type: cdn
languages: [rust]
capabilities: [env-vars, secrets]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/variables_and_secrets
---

# Feature: Environment Variables and Secrets (CDN, Rust)

## When to Use

Use this feature when a CDN app must read runtime configuration from environment variables or secrets — for example, to forward credentials or config values as upstream request headers.

## Dependencies

```toml
[dependencies]
proxy-wasm = "0.2"
fastedge = { version = "0.4", features = ["proxywasm"] }
```

Crate type must be `cdylib`:

```toml
[lib]
crate-type = ["cdylib"]
```

## Imports

```rust
use fastedge::proxywasm::secret;
use std::env;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
```

## Entrypoint

```rust
proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(VariablesRoot) });
}}
```

## Root Context

```rust
struct VariablesRoot;

impl Context for VariablesRoot {}

impl RootContext for VariablesRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(VariablesContext))
    }
}
```

## HTTP Context

```rust
struct VariablesContext;

impl Context for VariablesContext {}

impl HttpContext for VariablesContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let username = env::var("USERNAME").unwrap_or_default();
        let password = secret::get("PASSWORD")
            .ok()
            .flatten()
            .and_then(|v| String::from_utf8(v).ok())
            .unwrap_or_default();

        self.add_http_request_header("x-env-username", &username);
        self.add_http_request_header("x-env-password", &password);

        Action::Continue
    }
}
```

## API Reference

### `std::env::var`

```rust
env::var(key: &str) -> Result<String, VarError>
```

- Reads an environment variable by name.
- Use `.unwrap_or_default()` for safe fallback to an empty string when the variable is absent.

### `fastedge::proxywasm::secret::get`

```rust
secret::get(name: &str) -> Result<Option<Vec<u8>>, u32>
```

- Reads a secret by name from the FastEdge secrets store.
- Returns `Ok(Some(bytes))` on success, `Ok(None)` if not found, `Err(u32)` on error.
- Convert bytes to `String`:

```rust
secret::get("PASSWORD")
    .ok()           // discard Err, yield Option<Option<Vec<u8>>>
    .flatten()      // yield Option<Vec<u8>>
    .and_then(|v| String::from_utf8(v).ok())  // yield Option<String>
    .unwrap_or_default()  // yield String, empty on any failure
```

### `HttpContext::add_http_request_header`

```rust
self.add_http_request_header(name: &str, value: &str)
```

- Adds a header to the outgoing request sent to the upstream origin.
- Called within `on_http_request_headers`; changes take effect before the request is forwarded.

## CDN Hook Pattern

All reads and header mutations occur in `on_http_request_headers`. No body hooks are required for this feature.

| Hook | Purpose |
|---|---|
| `on_http_request_headers` | Read env vars and secrets; set upstream request headers |

## Required App Configuration

| Type | Key | Description |
|---|---|---|
| Environment variable | `USERNAME` | Forwarded as `x-env-username` header |
| Secret | `PASSWORD` | Forwarded as `x-env-password` header |

Configure environment variables and secrets in the FastEdge app settings before deployment.

## Logging

```rust
println!("USERNAME: {}", username);
println!("PASSWORD: {}", password);
```

- `println!` maps to the platform log output in the proxy-wasm CDN context.
- WARNING: Secrets are stored and retrieved as plaintext. Never log secret values in production — platform logs are visible to operators and may be persisted. The logging of `PASSWORD` above is for demonstration only; remove it in any real application.
- WARNING: Forwarding a secret in a request header exposes it to the upstream origin and any intermediary that can inspect headers. Only do this when the upstream channel is trusted and the header is required by the destination API.

## Security Notes

- Secret values are retrieved as raw bytes (`Vec<u8>`) and must be explicitly converted to `String`. Conversion failure produces an empty string via `.unwrap_or_default()`.
- Do not log secret values in production code.
- Only forward secrets as headers when the upstream channel is trusted and the destination API requires it.

## See Also

- cdn-base skeleton (base proxy-wasm CDN app structure)
- FastEdge app secrets management (platform docs)
- proxy-wasm HttpContext trait reference
- fastedge crate proxywasm feature documentation
