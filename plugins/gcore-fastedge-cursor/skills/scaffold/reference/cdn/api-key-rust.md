<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-07-23
-->

---
type: feature
app_type: cdn
languages: [rust]
capabilities: [auth, api-key]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/api_key
---

# Feature: API Key Authentication (CDN Rust)

## When to Use

Use this blueprint when the user needs API key validation at the CDN layer before requests reach origin. This is a proxy-wasm filter that intercepts HTTP requests, checks for an `X-API-Key` header, validates it against a stored secret, and strips the header before forwarding to upstream. Simpler alternative to JWT when token expiry and claims are not needed.

## Dependencies to Add

No additional dependencies beyond the base `cdn-base` skeleton. The `fastedge` crate with the `proxywasm` feature is sufficient.

The base skeleton's `proxy-wasm = "0.2"` and `fastedge = { version = "0.4", features = ["proxywasm"] }` cover all requirements.

## Files to Create

No extra files beyond the main source file are needed. The API key example is self-contained.

## Files to Modify

### src/lib.rs (or api_key.rs)

The example uses `[lib]` with `crate-type = ["cdylib"]`. In the base skeleton, replace the main source file content.

**Replace with:**
```rust
use fastedge::proxywasm::secret;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(ApiKeyRoot) });
}}

struct ApiKeyRoot;

impl Context for ApiKeyRoot {}

impl RootContext for ApiKeyRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(ApiKeyContext))
    }
}

struct ApiKeyContext;

impl Context for ApiKeyContext {}

impl HttpContext for ApiKeyContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let expected_key = match secret::get("API_KEY") {
            Ok(Some(bytes)) => match String::from_utf8(bytes) {
                Ok(s) if !s.is_empty() => s,
                _ => {
                    self.send_http_response(500, vec![], Some(b"App misconfigured"));
                    return Action::Pause;
                }
            },
            _ => {
                self.send_http_response(500, vec![], Some(b"App misconfigured"));
                return Action::Pause;
            }
        };

        let provided_key = match self.get_http_request_header("X-API-Key") {
            Some(k) if !k.is_empty() => k,
            _ => {
                self.send_http_response(
                    401,
                    vec![("WWW-Authenticate", "API-Key")],
                    Some(b"Missing X-API-Key header"),
                );
                return Action::Pause;
            }
        };

        if provided_key != expected_key {
            println!("API key validation failed");
            self.send_http_response(403, vec![], Some(b"Invalid API key"));
            return Action::Pause;
        }

        // Strip the API key header before forwarding to upstream
        self.set_http_request_header("X-API-Key", None);

        println!("API key validated successfully");
        Action::Continue
    }
}
```

### Cargo.toml

**Full example Cargo.toml** (edition 2024):
```toml
[workspace]

[package]
name = "api_key"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
fastedge = { version = "0.4", features = ["proxywasm"] }
```

## API Key Validation Flow

The `on_http_request_headers` hook executes the following steps in order:

1. **Secret retrieval** — `secret::get("API_KEY")` fetches the expected API key from FastEdge secrets. Returns 500 if absent, non-UTF-8, or empty.
2. **Header extraction** — `self.get_http_request_header("X-API-Key")` retrieves the provided key. Returns 401 with `WWW-Authenticate: API-Key` header if missing or empty.
3. **Key comparison** — Compares provided key against expected key with `!=`. Returns 403 if they do not match.
4. **Header stripping** — `self.set_http_request_header("X-API-Key", None)` removes the header before forwarding to upstream.
5. **Allow** — Returns `Action::Continue` if all checks pass.

## Required Secrets

| Secret Name | Type   | Description |
|-------------|--------|-------------|
| `API_KEY`   | String | The expected API key value. Compared directly against the `X-API-Key` request header. |

Secrets are accessed via `fastedge::proxywasm::secret::get("API_KEY")`. This is distinct from environment variables — secrets are configured in the FastEdge dashboard under the app's secret variables.

## Key Patterns

- **`proxy_wasm::main!`** macro — CDN app entry point; sets log level and registers the root context. CDN equivalent of `#[fastedge::http]` used in HTTP apps.
- **`RootContext` trait** — factory that creates per-request `HttpContext` instances via `create_http_context`.
- **`HttpContext` trait** — per-request filter; implements `on_http_request_headers`.
- **`on_http_request_headers(&mut self, _: usize, _: bool) -> Action`** — primary filter hook for CDN apps; all validation occurs here.
- **`Action::Continue`** — allows the request to proceed to origin.
- **`Action::Pause` + `send_http_response`** — rejects the request; no further processing occurs.
- **`self.send_http_response(status: u32, headers: Vec<(&str, &str)>, body: Option<&[u8]>)`** — sends an immediate HTTP response to the client.
- **`fastedge::proxywasm::secret::get(name: &str) -> Result<Option<Vec<u8>>, _>`** — reads a secret variable by name; returns raw bytes.
- **`self.get_http_request_header(name: &str) -> Option<String>`** — retrieves a request header value by name.
- **`self.set_http_request_header(name: &str, value: Option<&str>)`** — sets or removes a request header. Pass `None` to strip the header before forwarding.
- **`println!`** — used for log output within CDN filter hooks (e.g. validation success/failure messages).

## Secret Retrieval Pattern

`secret::get` returns `Result<Option<Vec<u8>>, _>`. Safe conversion to a non-empty `String`:

```rust
let expected_key = match secret::get("API_KEY") {
    Ok(Some(bytes)) => match String::from_utf8(bytes) {
        Ok(s) if !s.is_empty() => s,
        _ => {
            self.send_http_response(500, vec![], Some(b"App misconfigured"));
            return Action::Pause;
        }
    },
    _ => {
        self.send_http_response(500, vec![], Some(b"App misconfigured"));
        return Action::Pause;
    }
};
```

Both the `Err(_)` case and `Ok(None)` case (secret not configured) are handled identically — return 500.

## HTTP Status Code Reference

| Code | Condition |
|------|-----------|
| 401  | `X-API-Key` header missing or empty; response includes `WWW-Authenticate: API-Key` header |
| 403  | `X-API-Key` header present but does not match the stored secret |
| 500  | `API_KEY` secret not configured, not valid UTF-8, or empty |

## Build Notes

Standard Rust WASM build:

```bash
cargo build --release --target wasm32-wasip1
```

Requires `.cargo/config.toml`:
```toml
[build]
target = "wasm32-wasip1"
```

## See Also

- cdn-base skeleton reference (base dependencies and project structure for CDN apps)
- FastEdge SDK Rust reference (proxywasm module, secret API)
- FastEdge secrets configuration (dashboard secret variable setup)
- auth-jwt-rust reference (JWT-based authentication — use when token expiry and claims are needed)
- platform-overview reference (CDN vs HTTP app type distinction)
