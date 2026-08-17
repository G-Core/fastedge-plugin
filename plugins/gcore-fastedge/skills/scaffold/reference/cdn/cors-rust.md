<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-08-17
-->

---
type: feature
app_type: cdn
languages: [rust]
capabilities: [cors, preflight]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/cors
---

# Feature: CORS (CDN Rust)

## When to Use

Use this blueprint when the user wants to handle CORS preflight requests and add CORS response headers at the CDN layer. This is a proxy-wasm filter that validates the `Origin` request header against a configurable allow-list, responds to `OPTIONS` preflight requests directly with `204 No Content`, and injects `Access-Control-*` headers into all non-preflight responses for allowed origins.

## Dependencies to Add

No extra dependencies beyond the base `cdn-base` skeleton. The base skeleton's `Cargo.toml` already includes `proxy-wasm`. No additional crates are required.

Source `Cargo.toml` for reference:
```toml
[workspace]

[package]
name = "cors"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
```

## Files to Create

No extra files beyond the main source file. The CORS example is self-contained in a single source file.

## Files to Modify

### src/lib.rs

The example uses `[lib]` with `crate-type = ["cdylib"]`. Replace the base skeleton's main source file with the following implementation.

**Replace with:**
```rust
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::env;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(CorsRoot) });
}}

struct CorsRoot;

impl Context for CorsRoot {}

impl RootContext for CorsRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(CorsContext))
    }
}

struct CorsContext;

impl Context for CorsContext {}

impl HttpContext for CorsContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let origin = match self.get_http_request_header("Origin") {
            Some(o) if !o.is_empty() => o,
            _ => return Action::Continue,
        };

        let allowed_origins = env::var("ALLOWED_ORIGINS").unwrap_or_default();
        if !is_origin_allowed(&origin, &allowed_origins) {
            return Action::Continue;
        }

        // Handle preflight OPTIONS request
        let method = self
            .get_http_request_header(":method")
            .unwrap_or_default();

        if method == "OPTIONS" {
            let allow_methods = env::var("ALLOWED_METHODS")
                .unwrap_or_else(|_| "GET, POST, PUT, DELETE, OPTIONS".to_string());
            let allow_headers = self
                .get_http_request_header("Access-Control-Request-Headers")
                .unwrap_or_else(|| "Content-Type, Authorization".to_string());
            let max_age = env::var("MAX_AGE").unwrap_or_else(|_| "86400".to_string());

            let effective_origin = if allowed_origins == "*" {
                "*".to_string()
            } else {
                origin
            };

            let mut headers = vec![
                ("Access-Control-Allow-Origin", effective_origin.as_str()),
                ("Access-Control-Allow-Methods", allow_methods.as_str()),
                ("Access-Control-Allow-Headers", allow_headers.as_str()),
                ("Access-Control-Max-Age", max_age.as_str()),
                ("Content-Length", "0"),
            ];

            // Vary: Origin is needed when the response varies by origin,
            // so shared caches don't serve a cached response for a different origin.
            // Not needed when Allow-Origin is "*" (response is the same for all origins).
            if effective_origin != "*" {
                headers.push(("Vary", "Origin"));
            }

            self.send_http_response(204, headers, None);

            return Action::Pause;
        }

        Action::Continue
    }

    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        let origin = match self.get_http_request_header("Origin") {
            Some(o) if !o.is_empty() => o,
            _ => return Action::Continue,
        };

        let allowed_origins = env::var("ALLOWED_ORIGINS").unwrap_or_default();
        if !is_origin_allowed(&origin, &allowed_origins) {
            return Action::Continue;
        }

        let effective_origin = if allowed_origins == "*" {
            "*".to_string()
        } else {
            origin
        };

        self.add_http_response_header("Access-Control-Allow-Origin", &effective_origin);
        if effective_origin != "*" {
            self.add_http_response_header("Vary", "Origin");
        }

        if let Ok(expose) = env::var("EXPOSE_HEADERS") {
            if !expose.is_empty() {
                self.add_http_response_header("Access-Control-Expose-Headers", &expose);
            }
        }

        Action::Continue
    }
}

fn is_origin_allowed(origin: &str, allowed: &str) -> bool {
    if allowed.is_empty() {
        return false;
    }
    if allowed == "*" {
        return true;
    }
    allowed.split(',').any(|o| o.trim() == origin)
}
```

### Cargo.toml

No additional dependencies beyond the base skeleton. Ensure `crate-type = ["cdylib"]` is set under `[lib]`. The base skeleton includes `log = "0.4"` which is not required by this example — it may be removed.

## Required Environment Variables

Configure these in the FastEdge dashboard under the app's environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `ALLOWED_ORIGINS` | Yes (functional) | Comma-separated list of allowed origins (e.g. `https://example.com,https://app.example.com`) or `"*"` for wildcard. When unset or empty the filter is dormant — requests pass through without CORS headers, so browsers will block cross-origin access. |
| `ALLOWED_METHODS` | No | Comma-separated HTTP methods for preflight response (default: `GET, POST, PUT, DELETE, OPTIONS`) |
| `MAX_AGE` | No | Preflight cache duration in seconds (default: `86400`) |
| `EXPOSE_HEADERS` | No | Comma-separated list of response headers to expose via `Access-Control-Expose-Headers` (omitted if not set or empty) |

## Error Conditions

| Condition | Behaviour |
|-----------|-----------|
| `ALLOWED_ORIGINS` not set or empty | `env::var` returns `Err`; `unwrap_or_default()` produces empty string; `is_origin_allowed` returns `false`; filter is dormant — requests pass through without CORS headers |
| Request has no `Origin` header or empty `Origin` | Filter returns `Action::Continue` immediately — no CORS headers added |
| `Origin` not in allow-list | `is_origin_allowed` returns `false`; filter returns `Action::Continue` — no CORS headers added |
| Valid `OPTIONS` preflight from allowed origin | Filter responds with `204` and `Access-Control-*` headers, returns `Action::Pause` — request does not reach origin |
| Valid non-OPTIONS request from allowed origin | Filter adds `Access-Control-Allow-Origin` (and optionally `Vary`, `Access-Control-Expose-Headers`) in response phase; returns `Action::Continue` |

## Key Patterns

- **`proxy_wasm::main!`** macro — CDN app entry point. Sets log level (`LogLevel::Info`) and registers the root context factory. Not `#[fastedge::http]`.
- **`RootContext` + `HttpContext` trait pair** — `RootContext` creates per-request `HttpContext` instances via `create_http_context`. Both must also implement the `Context` trait.
- **`get_type()`** — must return `Some(ContextType::HttpContext)` on `RootContext` for the proxy-wasm runtime to route HTTP filter callbacks.
- **`on_http_request_headers(&mut self, _: usize, _: bool) -> Action`** — request-phase hook. Handles preflight detection and direct response for `OPTIONS`. Returns `Action::Continue` for non-preflight or non-matching origins.
- **`on_http_response_headers(&mut self, _: usize, _: bool) -> Action`** — response-phase hook. Adds `Access-Control-Allow-Origin` and optional CORS headers to responses for allowed origins.
- **Dual-hook CDN pattern** — this example uses both `on_http_request_headers` (preflight interception) and `on_http_response_headers` (CORS headers on normal responses). This is distinct from single-hook CDN filters.
- **`self.get_http_request_header("Origin")`** — reads the `Origin` request header. Returns `Option<String>`. Also used inside `on_http_response_headers` to re-read the request origin — the request header is accessible from both request and response phases.
- **`self.get_http_request_header(":method")`** — reads the HTTP method via the `:method` pseudo-header (HTTP/2 style). Returns `Option<String>`.
- **`self.send_http_response(204, headers, None)`** — sends a synthetic preflight response. `headers` is `Vec<(&str, &str)>`. `None` body produces a zero-length body. Pair with `Action::Pause` to prevent the request from reaching origin.
- **`self.add_http_response_header(name, value)`** — appends a header to the upstream response. Used in `on_http_response_headers`.
- **`effective_origin` logic** — when `ALLOWED_ORIGINS == "*"`, the response header is set to `"*"` rather than the actual request origin. When `ALLOWED_ORIGINS` is a specific list, the actual request `Origin` value is echoed back.
- **`Vary: Origin` header** — added to both preflight and non-preflight responses when `effective_origin != "*"`. Signals to shared caches that the response varies by `Origin` value. Not added for wildcard `*` responses.
- **`is_origin_allowed(origin, allowed)` helper** — returns `false` if `allowed` is empty, `true` if `allowed == "*"`, otherwise splits on `,` and compares trimmed segments to `origin` (exact, case-sensitive match).
- **`env::var` at request time** — all env vars are read per-request, not at startup. Changes to env vars take effect on the next request without redeployment.
- **`Access-Control-Request-Headers` fallback** — for preflight `Allow-Headers`, the value from the request's `Access-Control-Request-Headers` header is used when present; fallback default is `"Content-Type, Authorization"`.

## Preflight Response Headers

Headers sent on a `204` preflight response from an allowed origin:

| Header | Value Source |
|--------|-------------|
| `Access-Control-Allow-Origin` | `"*"` or echoed request `Origin` |
| `Access-Control-Allow-Methods` | `ALLOWED_METHODS` env var or default `GET, POST, PUT, DELETE, OPTIONS` |
| `Access-Control-Allow-Headers` | `Access-Control-Request-Headers` request header or `"Content-Type, Authorization"` |
| `Access-Control-Max-Age` | `MAX_AGE` env var or `"86400"` |
| `Content-Length` | `"0"` |
| `Vary` | `"Origin"` (only when not using wildcard `*`) |

## Non-Preflight Response Headers

Headers added in `on_http_response_headers` for non-OPTIONS requests from allowed origins:

| Header | Value Source | Condition |
|--------|-------------|-----------|
| `Access-Control-Allow-Origin` | `"*"` or echoed request `Origin` | Always (for allowed origins) |
| `Vary` | `"Origin"` | Only when not using wildcard `*` |
| `Access-Control-Expose-Headers` | `EXPOSE_HEADERS` env var | Only when `EXPOSE_HEADERS` is set and non-empty |

## Build Notes

Standard Rust CDN build:

```bash
cargo build --release --target wasm32-wasip1
```

Requires `.cargo/config.toml`:
```toml
[build]
target = "wasm32-wasip1"
```

Output binary: `target/wasm32-wasip1/release/cors.wasm`

## See Also

- cdn-base skeleton reference (base proxy-wasm project structure for Rust CDN apps)
- FastEdge SDK Rust reference (proxy-wasm trait definitions, Action type, HttpContext callbacks)
- headers-rust reference (simpler single-hook CDN filter for header manipulation)
- deploy skill reference (uploading and registering the compiled WASM binary)
- Platform overview reference (environment variable configuration)
