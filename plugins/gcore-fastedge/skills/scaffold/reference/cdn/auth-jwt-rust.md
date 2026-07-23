<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-06-16
-->

---
type: feature
app_type: cdn
languages: [rust]
capabilities: [auth, jwt]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/jwt
---

# Feature: JWT Authentication (CDN Rust)

## When to Use

Use this blueprint when the user needs JWT token validation at the CDN layer before requests reach origin. This is a proxy-wasm filter that intercepts HTTP requests, extracts a Bearer token from the `Authorization` header, validates it using a shared HMAC secret (stored in FastEdge secrets), and checks expiration. Invalid or expired tokens are rejected with appropriate HTTP status codes.

## Dependencies to Add

These dependencies go **beyond** the base `cdn-base` skeleton's deps:

```toml
[dependencies]
jsonwebtoken = "9"
serde = { version = "1", features = ["derive"] }
headers = "0.4"
```

The base skeleton already provides `proxy-wasm`, `fastedge` (with `proxywasm` feature), and `log`.

## Files to Create

No extra files beyond the main source file are needed. The JWT example is self-contained.

## Files to Modify

### lib.rs (or jwt.rs)

The example uses `[lib]` with `crate-type = ["cdylib"]`. In the base skeleton, replace the main source file content.

**Replace with:**
```rust
use std::time::{SystemTime, UNIX_EPOCH};
use headers::HeaderValue;
use headers::authorization::{Bearer, Credentials};

use fastedge::proxywasm::secret;
use jsonwebtoken::{decode, DecodingKey, Validation};
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use serde::Deserialize;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpHeadersRoot) });
}}

struct HttpHeadersRoot;

impl Context for HttpHeadersRoot {}

impl RootContext for HttpHeadersRoot {
    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpHeaders {}))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct HttpHeaders {}

impl Context for HttpHeaders {}

const UNAUTHORIZED: u32 = 401;
const FORBIDDEN: u32 = 403;
const INTERNAL_SERVER_ERROR: u32 = 500;

#[derive(Debug, Deserialize, Default)]
struct Claims {
    exp: u64,
}

impl HttpContext for HttpHeaders {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let Ok(Some(secret)) = secret::get("secret") else {
            println!("'secret' param not set");
            self.send_http_response(INTERNAL_SERVER_ERROR, vec![], Some(b"App misconfigured"));
            return Action::Pause;
        };
        let Some(value) = self.get_http_request_header("Authorization") else {
            println!("No auth header");
            self.send_http_response(UNAUTHORIZED, vec![], Some(b"No Authorization header"));
            return Action::Pause;
        };

        if value.is_empty() {
            println!("Auth header is empty");
            self.send_http_response(UNAUTHORIZED, vec![], Some(b"No Authorization header"));
            return Action::Pause;
        };

        let Ok(header) = value.parse::<HeaderValue>() else {
            println!("Auth header is invalid");
            self.send_http_response(UNAUTHORIZED, vec![], Some(b"Invalid Authorization header"));
            return Action::Pause;
        };

        let Some(bearer) = Bearer::decode(&header) else {
            println!("Auth header doesn't contain token");
            self.send_http_response(FORBIDDEN, vec![], Some(b"Token not found"));
            return Action::Pause;
        };

        let token = bearer.token();

        let decoding_key = DecodingKey::from_secret(&secret);
        let mut validation = Validation::default();
        validation.set_required_spec_claims(&["exp"]);
        // skip validation of aud and nbf claims
        validation.validate_aud = false;
        validation.validate_nbf = false;
        validation.validate_exp = false;  // will validate expiration separately

        let token_data = match decode::<Claims>(token, &decoding_key, &validation) {
            Ok(token_data) => token_data,
            Err(error) => {
                println!("Token is invalid");
                self.send_http_response(FORBIDDEN, vec![], Some(format!("Could not decode token {}: {}", token, error).as_bytes()));
                return Action::Pause;
            }
        };

        let claims = token_data.claims;

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        if now > claims.exp {
            println!("Token expired");
            self.send_http_response(FORBIDDEN, vec![], Some(b"Token expired"));
            return Action::Pause;
        }

        println!("Token ok");
        Action::Continue
    }
}
```

### Cargo.toml

**Full example Cargo.toml** (edition 2024):
```toml
[workspace]

[package]
name = "jwt"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
fastedge = { version = "0.4", features = ["proxywasm"] }
jsonwebtoken = "9"
serde = { version = "1", features = ["derive"] }
headers = "0.4"
```

## JWT Validation Flow

The `on_http_request_headers` hook executes the following steps in order:

1. **Secret retrieval** — `secret::get("secret")` fetches the HMAC key from FastEdge secrets. Returns `INTERNAL_SERVER_ERROR` (500) if absent.
2. **Header extraction** — `self.get_http_request_header("Authorization")` retrieves the raw header value. Returns `UNAUTHORIZED` (401) if missing.
3. **Empty check** — Returns `UNAUTHORIZED` (401) if the header value is present but empty.
4. **Header parsing** — `value.parse::<HeaderValue>()` parses the raw string. Returns `UNAUTHORIZED` (401) if malformed.
5. **Bearer extraction** — `Bearer::decode(&header)` extracts the token from `Authorization: Bearer <token>`. Returns `FORBIDDEN` (403) if the scheme is not Bearer or token is absent.
6. **Signature verification** — `decode::<Claims>(token, &decoding_key, &validation)` decodes and verifies the JWT signature using HMAC. Returns `FORBIDDEN` (403) on decode failure.
7. **Expiration check** — Compares `SystemTime::now()` (as Unix seconds) against `claims.exp`. Returns `FORBIDDEN` (403) if expired.
8. **Allow** — Returns `Action::Continue` if all checks pass.

## Required Secrets

| Secret Name | Type     | Description |
|-------------|----------|-------------|
| `secret`    | HMAC key | Shared secret for JWT signature validation. Minimum 256 bits recommended. |

Secrets are accessed via `fastedge::proxywasm::secret::get("secret")`. This is distinct from environment variables — secrets are configured in the FastEdge dashboard under the app's secret variables.

## Key Patterns

- **`proxy_wasm::main!`** macro — CDN app entry point; sets log level and registers the root context. This is the CDN equivalent of `#[fastedge::http]` used in HTTP apps.
- **`RootContext` trait** — factory that creates per-request `HttpContext` instances via `create_http_context`.
- **`HttpContext` trait** — per-request filter; implements `on_http_request_headers`.
- **`on_http_request_headers(&mut self, _: usize, _: bool) -> Action`** — primary filter hook for CDN apps; intercepts all inbound request headers.
- **`Action::Continue`** — allows the request to proceed to origin.
- **`Action::Pause` + `send_http_response`** — rejects the request; no further processing occurs.
- **`self.send_http_response(status: u32, headers: Vec<...>, body: Option<&[u8]>)`** — sends an immediate HTTP response to the client.
- **`fastedge::proxywasm::secret::get(name: &str) -> Result<Option<Vec<u8>>, _>`** — reads a secret variable by name.
- **`Bearer::decode(&HeaderValue) -> Option<Bearer>`** — from the `headers` crate; extracts Bearer token from Authorization header.
- **`DecodingKey::from_secret(&[u8])`** — constructs HMAC decoding key from raw bytes.
- **`Validation`** — configures JWT validation behavior:
  - `set_required_spec_claims(&["exp"])` — requires `exp` claim to be present
  - `validate_aud = false` — skips audience validation
  - `validate_nbf = false` — skips not-before validation
  - `validate_exp = false` — disables library-level expiration check (manual check performed instead)
- **Manual expiration check** — `SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()` compared against `claims.exp` (u64 Unix timestamp).

## Claims Struct

```rust
#[derive(Debug, Deserialize, Default)]
struct Claims {
    exp: u64,
}
```

Only `exp` is extracted. Additional claims can be added to this struct as needed (with corresponding `Deserialize` fields).

## HTTP Status Code Reference

| Code | Constant                | Condition |
|------|-------------------------|-----------|
| 401  | `UNAUTHORIZED`          | Missing Authorization header; empty header value; malformed header value |
| 403  | `FORBIDDEN`             | No Bearer token; JWT decode failure; token expired |
| 500  | `INTERNAL_SERVER_ERROR` | `secret` variable not configured |

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
- platform-overview reference (CDN vs HTTP app type distinction)
