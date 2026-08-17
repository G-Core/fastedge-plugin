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
capabilities: [geo-routing, geoblock]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/geoblock
---

# Feature: Geo Block (CDN Rust)

## When to Use

Use this blueprint when the user needs country-based request blocking on a CDN app. This is a proxy-wasm filter that reads the client's country from the `request.country` property, checks it against a configurable blacklist (env var), and optionally applies a time window for the block. Requests from blacklisted countries are rejected with `403 Forbidden`.

## Dependencies to Add

No extra dependencies beyond the base `cdn-base` skeleton. The base skeleton's `Cargo.toml` already includes `proxy-wasm`. No additional crates are required.

Source `Cargo.toml` for reference:
```toml
[workspace]

[package]
name = "geoblock"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
```

## Files to Create

No extra files beyond the main source file. The geoblock example is self-contained in a single source file.

## Files to Modify

### lib.rs

The example uses `[lib]` with `crate-type = ["cdylib"]`. In the base skeleton, rename or replace the main source file with the following implementation.

**Replace with:**
```rust
use std::env;
use std::time::{SystemTime, UNIX_EPOCH};

use proxy_wasm::traits::*;
use proxy_wasm::types::*;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(GeoblockRoot) });
}}

struct GeoblockRoot;

impl Context for GeoblockRoot {}

impl RootContext for GeoblockRoot {
    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(GeoblockContext {}))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct GeoblockContext {}

impl Context for GeoblockContext {}

const BAD_GATEWAY: u32 = 502;
const FORBIDDEN: u32 = 403;
const INTERNAL_SERVER_ERROR: u32 = 500;

impl HttpContext for GeoblockContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let Ok(blacklist) = env::var("BLACKLIST") else {
            self.send_http_response(INTERNAL_SERVER_ERROR, vec![], Some(b"App misconfigured"));
            return Action::Pause;
        };

        let mut blacklist = blacklist.split(',');

        let Some(country) = self.get_property(vec!["request.country"]) else {
            self.send_http_response(BAD_GATEWAY, vec![], Some(b"Malformed request - no country field"));
            return Action::Pause;
        };

        let Ok(country) = std::str::from_utf8(&country) else {
            self.send_http_response(BAD_GATEWAY, vec![], Some(b"Malformed request - country not utf8 string"));
            return Action::Pause;
        };

        if blacklist.any(|b| country.eq_ignore_ascii_case(b)) {
            let tw_start = env::var("BLACKLIST_TW_START").ok();
            let tw_end = env::var("BLACKLIST_TW_END").ok();

            if let Some((tw_start, tw_end)) = tw_start.zip(tw_end) {
                let Ok(tw_start) = tw_start.parse::<u64>() else {
                    self.send_http_response(INTERNAL_SERVER_ERROR, vec![], Some(b"App misconfigured"));
                    return Action::Pause;
                };

                let Ok(tw_end) = tw_end.parse::<u64>() else {
                    self.send_http_response(INTERNAL_SERVER_ERROR, vec![], Some(b"App misconfigured"));
                    return Action::Pause;
                };

                let now = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs();

                if now >= tw_start && now <= tw_end {
                    self.send_http_response(FORBIDDEN, vec![], Some(b"Request blacklisted"));
                    return Action::Pause;
                }
            } else {
                self.send_http_response(FORBIDDEN, vec![], Some(b"Request blacklisted"));
                return Action::Pause;
            }
        }

        Action::Continue
    }
}
```

### Cargo.toml

No additional dependencies beyond the base skeleton. Ensure `crate-type = ["cdylib"]` is set under `[lib]`.

## Required Environment Variables

Configure these in the FastEdge dashboard under the app's environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `BLACKLIST` | Yes | Comma-separated list of ISO country codes to block (e.g. `RU,CN,KP`) |
| `BLACKLIST_TW_START` | No | Unix timestamp (u64) — start of time window during which blocking applies |
| `BLACKLIST_TW_END` | No | Unix timestamp (u64) — end of time window during which blocking applies |

If both `BLACKLIST_TW_START` and `BLACKLIST_TW_END` are set, the block only applies during that time window (`now >= tw_start && now <= tw_end`). If neither is set, the block is permanent for all listed countries. If only one of the two time-window variables is set, it is treated as absent and the block is permanent.

## Error Conditions

| Condition | Response Code | Body |
|-----------|---------------|------|
| `BLACKLIST` env var missing | 500 | `App misconfigured` |
| `BLACKLIST_TW_START` present but not a valid `u64` | 500 | `App misconfigured` |
| `BLACKLIST_TW_END` present but not a valid `u64` | 500 | `App misconfigured` |
| `request.country` property absent | 502 | `Malformed request - no country field` |
| `request.country` property not valid UTF-8 | 502 | `Malformed request - country not utf8 string` |
| Country is in blacklist (with or without active time window) | 403 | `Request blacklisted` |
| Country not in blacklist | — | `Action::Continue` (request passes through) |

## Key Patterns

- **`proxy_wasm::main!`** macro — CDN app entry point. Sets log level and registers the root context. Not `#[fastedge::http]`.
- **`RootContext` + `HttpContext` trait pair** — `RootContext` creates per-request `HttpContext` instances via `create_http_context`. Both must implement the `Context` trait.
- **`get_type()`** — must return `Some(ContextType::HttpContext)` on `RootContext` for the proxy-wasm runtime to route HTTP filter callbacks.
- **`on_http_request_headers(&mut self, _: usize, _: bool) -> Action`** — the filter hook. Called on every inbound request's headers phase. Return `Action::Continue` to allow; call `send_http_response` then return `Action::Pause` to reject.
- **`self.get_property(vec!["request.country"])`** — reads the client's country code injected by the FastEdge platform. Returns `Option<Vec<u8>>`.
- **`std::str::from_utf8(&country)`** — converts the raw property bytes to a string slice for comparison.
- **`std::env::var("BLACKLIST")`** — reads the blacklist from environment variables at request time (not at startup).
- **`blacklist.split(',')`** — parses the comma-separated country code list into an iterator.
- **`eq_ignore_ascii_case`** — case-insensitive country code comparison.
- **`tw_start.zip(tw_end)`** — both time-window variables must be present for time-window logic to activate; if only one is set, it is treated as absent and the block is permanent.
- **`send_http_response(status, headers, body)`** — sends a synthetic response. `headers` is `vec![]` (no extra headers). `body` is `Option<&[u8]>`.
- **Time-window condition**: `now >= tw_start && now <= tw_end` — an AND condition. The block applies only when the current time is within the inclusive range `[tw_start, tw_end]`. Outside that range, the request passes through even for blacklisted countries.

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

Output binary: `target/wasm32-wasip1/release/<crate-name>.wasm`

## See Also

- cdn-base skeleton reference (base proxy-wasm project structure)
- FastEdge SDK Rust reference (proxy-wasm trait definitions and types)
- Platform overview reference (request.country property and other injected properties)
- deploy skill reference (uploading and registering the compiled WASM binary)

## Source Material

### FILE: examples/cdn/geoblock/src/lib.rs

```rust
use std::env;
use std::time::{SystemTime, UNIX_EPOCH};

use proxy_wasm::traits::*;
use proxy_wasm::types::*;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(GeoblockRoot) });
}}

struct GeoblockRoot;

impl Context for GeoblockRoot {}

impl RootContext for GeoblockRoot {
    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(GeoblockContext {}))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct GeoblockContext {}

impl Context for GeoblockContext {}

const BAD_GATEWAY: u32 = 502;
const FORBIDDEN: u32 = 403;
const INTERNAL_SERVER_ERROR: u32 = 500;

impl HttpContext for GeoblockContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let Ok(blacklist) = env::var("BLACKLIST") else {
            self.send_http_response(INTERNAL_SERVER_ERROR, vec![], Some(b"App misconfigured"));
            return Action::Pause;
        };

        let mut blacklist = blacklist.split(',');

        let Some(country) = self.get_property(vec!["request.country"]) else {
            self.send_http_response(BAD_GATEWAY, vec![], Some(b"Malformed request - no country field"));
            return Action::Pause;
        };

        let Ok(country) = std::str::from_utf8(&country) else {
            self.send_http_response(BAD_GATEWAY, vec![], Some(b"Malformed request - country not utf8 string"));
            return Action::Pause;
        };

        if blacklist.any(|b| country.eq_ignore_ascii_case(b)) {
            let tw_start = env::var("BLACKLIST_TW_START").ok();
            let tw_end = env::var("BLACKLIST_TW_END").ok();

            if let Some((tw_start, tw_end)) = tw_start.zip(tw_end) {
                let Ok(tw_start) = tw_start.parse::<u64>() else {
                    self.send_http_response(INTERNAL_SERVER_ERROR, vec![], Some(b"App misconfigured"));
                    return Action::Pause;
                };

                let Ok(tw_end) = tw_end.parse::<u64>() else {
                    self.send_http_response(INTERNAL_SERVER_ERROR, vec![], Some(b"App misconfigured"));
                    return Action::Pause;
                };
                let now = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs();

                if now >= tw_start && now <= tw_end {
                    self.send_http_response(FORBIDDEN, vec![], Some(b"Request blacklisted"));
                    return Action::Pause;
                }
            } else {
                self.send_http_response(FORBIDDEN, vec![], Some(b"Request blacklisted"));
                return Action::Pause;
            }
        }


        Action::Continue
    }
}
```

### FILE: examples/cdn/geoblock/Cargo.toml

```toml
[workspace]

[package]
name = "geoblock"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
```
