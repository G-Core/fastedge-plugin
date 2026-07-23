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
capabilities: [cache-control, caching]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/cache_control
---

# Cache Control — CDN (Rust)

Sets `Cache-Control` response headers based on content type and HTTP response status. Implements tiered caching policy at the CDN layer, with optional configuration via environment variables.

## When to Use

Use this blueprint when you want content-type-aware `Cache-Control` headers applied to responses at the CDN edge — for example, long-lived immutable caching for static assets, short-lived revalidation for HTML, and no-cache for API responses.

## Cargo.toml

```toml
[package]
name = "cache_control"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
```

## Entry Point

```rust
proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(CacheControlRoot) });
}}
```

## Struct Layout

| Struct | Trait Impls | Role |
|---|---|---|
| `CacheControlRoot` | `Context`, `RootContext` | Creates per-request HTTP context |
| `CacheControlContext` | `Context`, `HttpContext` | Applies Cache-Control header logic |

## RootContext

```rust
impl RootContext for CacheControlRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(CacheControlContext))
    }
}
```

## HttpContext — on_http_response_headers

All cache logic executes in `on_http_response_headers`. Returns `Action::Continue` in all cases.

### Step 1 — Read Response Status

```rust
let status_code = self
    .get_property(vec!["response.status"])
    .and_then(|bytes| {
        if bytes.len() == 2 {
            Some(u16::from_be_bytes([bytes[0], bytes[1]]))
        } else {
            None
        }
    })
    .unwrap_or(200);
```

- `get_property(vec!["response.status"])` returns `Option<Vec<u8>>`.
- The value is a 2-byte big-endian `u16`. Decode with `u16::from_be_bytes([bytes[0], bytes[1]])`.
- Defaults to `200` if the property is absent or malformed.

### Step 2 — Short-circuit on Error Status

```rust
if !(200..400).contains(&status_code) {
    self.set_http_response_header("Cache-Control", Some("no-store"));
    return Action::Continue;
}
```

- Any status outside `200–399` (i.e. 4xx, 5xx) receives `Cache-Control: no-store` immediately. No further evaluation.

### Step 3 — Read Content-Type

```rust
let content_type = self
    .get_http_response_header("Content-Type")
    .unwrap_or_default();
```

### Step 4 — Read Environment Variables

| Variable | Default | Description |
|---|---|---|
| `STATIC_MAX_AGE` | `31536000` | `max-age` for static assets (seconds) |
| `HTML_MAX_AGE` | `3600` | `max-age` for HTML responses (seconds) |
| `API_MAX_AGE` | `0` | `max-age` for JSON/XML API responses; `0` = no-cache |

```rust
let static_max_age = env::var("STATIC_MAX_AGE").unwrap_or_else(|_| "31536000".to_string());
let html_max_age   = env::var("HTML_MAX_AGE").unwrap_or_else(|_| "3600".to_string());
let api_max_age    = env::var("API_MAX_AGE").unwrap_or_else(|_| "0".to_string());
```

### Step 5 — Caching Tiers

| Content Type | Cache-Control Value | Vary Header Added |
|---|---|---|
| Static asset (see `is_static_asset`) | `public, max-age=<STATIC_MAX_AGE>, immutable` | — |
| `text/html` | `public, max-age=<HTML_MAX_AGE>, must-revalidate` | `Accept-Encoding` |
| `application/json` or `application/xml`, `API_MAX_AGE == "0"` | `no-cache, no-store, must-revalidate` | `Accept, Authorization` |
| `application/json` or `application/xml`, `API_MAX_AGE != "0"` | `private, max-age=<API_MAX_AGE>, must-revalidate` | `Accept, Authorization` |
| All other content types | `public, max-age=600` | — |

```rust
let cache_control = if is_static_asset(&content_type) {
    format!("public, max-age={}, immutable", static_max_age)
} else if content_type.contains("text/html") {
    self.add_http_response_header("Vary", "Accept-Encoding");
    format!("public, max-age={}, must-revalidate", html_max_age)
} else if content_type.contains("application/json")
    || content_type.contains("application/xml")
{
    self.add_http_response_header("Vary", "Accept, Authorization");
    if api_max_age == "0" {
        "no-cache, no-store, must-revalidate".to_string()
    } else {
        format!("private, max-age={}, must-revalidate", api_max_age)
    }
} else {
    "public, max-age=600".to_string()
};

self.set_http_response_header("Cache-Control", Some(&cache_control));
```

### Step 6 — Log

```rust
println!(
    "Cache-Control: {} (content-type: {})",
    cache_control, content_type
);
```

Logs the applied `Cache-Control` value and the detected content type via `println!`. (Source uses `println!`, not `proxy_wasm::hostcalls::log`.)

## Helper: is_static_asset

```rust
fn is_static_asset(content_type: &str) -> bool {
    content_type.starts_with("image/")
        || content_type.starts_with("font/")
        || content_type.contains("application/javascript")
        || content_type.contains("text/css")
        || content_type.contains("text/javascript")
        || content_type.contains("application/wasm")
}
```

Matches content types classified as long-lived immutable static assets:

- `image/*` (any image subtype)
- `font/*` (any font subtype)
- `application/javascript`
- `text/css`
- `text/javascript`
- `application/wasm`

## Header Operations Summary

| Operation | Method | Header |
|---|---|---|
| Set Cache-Control | `set_http_response_header` | `Cache-Control` |
| Add Vary (HTML) | `add_http_response_header` | `Vary: Accept-Encoding` |
| Add Vary (API) | `add_http_response_header` | `Vary: Accept, Authorization` |

## Required Imports

```rust
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::env;
```

## Constraints

- All logic executes on the **response path** only (`on_http_response_headers`). No request-phase hooks are used.
- `get_property(vec!["response.status"])` must return exactly 2 bytes to decode correctly; any other length falls back to status `200`.
- `API_MAX_AGE` is compared as a string: only the exact string `"0"` triggers `no-cache, no-store, must-revalidate`. Any other string value (including `"00"`) is treated as a numeric age.
- `add_http_response_header` appends a header rather than replacing; if upstream already sets `Vary`, a second `Vary` value is added.

## See Also

- cdn-base skeleton (base CDN app structure)
- proxy-wasm HttpContext trait reference
- FastEdge-sdk-rust CDN examples overview
- host-services-rust reference (hostcalls, logging)

## Source Material

### FILE: examples/cdn/cache_control/src/lib.rs

```rust
/*
* Copyright 2025 G-Core Innovations SARL
*/
/*
Example CDN app demonstrating content-type-aware cache control.

Sets Cache-Control response headers based on the content type and
response status, providing fine-grained control over CDN caching.

Optional configuration:
  - Environment variable: STATIC_MAX_AGE (default: 31536000)
  - Environment variable: HTML_MAX_AGE (default: 3600)
  - Environment variable: API_MAX_AGE (default: 0 = no-cache)
*/

use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::env;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(CacheControlRoot) });
}}

struct CacheControlRoot;

impl Context for CacheControlRoot {}

impl RootContext for CacheControlRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(CacheControlContext))
    }
}

struct CacheControlContext;

impl Context for CacheControlContext {}

impl HttpContext for CacheControlContext {
    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        // Read response status
        let status_code = self
            .get_property(vec!["response.status"])
            .and_then(|bytes| {
                if bytes.len() == 2 {
                    Some(u16::from_be_bytes([bytes[0], bytes[1]]))
                } else {
                    None
                }
            })
            .unwrap_or(200);

        // Error responses should never be cached
        if !(200..400).contains(&status_code) {
            self.set_http_response_header("Cache-Control", Some("no-store"));
            return Action::Continue;
        }

        let content_type = self
            .get_http_response_header("Content-Type")
            .unwrap_or_default();

        let static_max_age = env::var("STATIC_MAX_AGE").unwrap_or_else(|_| "31536000".to_string());
        let html_max_age = env::var("HTML_MAX_AGE").unwrap_or_else(|_| "3600".to_string());
        let api_max_age = env::var("API_MAX_AGE").unwrap_or_else(|_| "0".to_string());

        let cache_control = if is_static_asset(&content_type) {
            format!("public, max-age={}, immutable", static_max_age)
        } else if content_type.contains("text/html") {
            self.add_http_response_header("Vary", "Accept-Encoding");
            format!("public, max-age={}, must-revalidate", html_max_age)
        } else if content_type.contains("application/json")
            || content_type.contains("application/xml")
        {
            self.add_http_response_header("Vary", "Accept, Authorization");
            if api_max_age == "0" {
                "no-cache, no-store, must-revalidate".to_string()
            } else {
                format!("private, max-age={}, must-revalidate", api_max_age)
            }
        } else {
            "public, max-age=600".to_string()
        };

        self.set_http_response_header("Cache-Control", Some(&cache_control));

        println!(
            "Cache-Control: {} (content-type: {})",
            cache_control, content_type
        );

        Action::Continue
    }
}

fn is_static_asset(content_type: &str) -> bool {
    content_type.starts_with("image/")
        || content_type.starts_with("font/")
        || content_type.contains("application/javascript")
        || content_type.contains("text/css")
        || content_type.contains("text/javascript")
        || content_type.contains("application/wasm")
}
```

### FILE: examples/cdn/cache_control/Cargo.toml

```toml
[workspace]

[package]
name = "cache_control"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
```

### FILE: examples/cdn/cache_control/README.md

```
[← Back to examples](../../README.md)

# Cache Control (CDN)

Sets `Cache-Control` response headers based on content type and response status, providing fine-grained control over CDN caching behaviour.
```
