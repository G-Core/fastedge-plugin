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
capabilities: [dictionary, large-config]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/large_env_variable
---

# Feature: Large Environment Variable via Dictionary (CDN, Rust)

## Purpose

Read environment variable values that may exceed the 64KB WASI environment variable size limit using `fastedge::proxywasm::dictionary::get`. Use this feature when your CDN app needs to access large configuration payloads (e.g. JSON configs, PEM certificates, policy documents).

## When to Use

| Method | Use when |
|--------|----------|
| `std::env::var("KEY")` | Variable value is under 64KB (most cases) |
| `fastedge::proxywasm::dictionary::get("KEY")` | Variable value may exceed the 64KB WASI env var size limit |

For all other environment variable access, prefer `std::env::var()` — it is the standard, idiomatic Rust approach.

## Required Dependencies

```toml
[dependencies]
proxy-wasm = "0.2"
fastedge = { version = "0.4", features = ["proxywasm"] }
```

The `proxywasm` feature flag must be enabled on the `fastedge` crate.

## Required Configuration

| Variable | Type | Description |
|----------|------|-------------|
| `LARGE_CONFIG` | String (any size) | Large configuration payload (e.g. JSON, PEM certificate). Set as a FastEdge environment variable. |

## API Reference

### `fastedge::proxywasm::dictionary::get`

```rust
pub fn get(name: &str) -> Option<String>
```

- **Parameters**: `name` — the environment variable key to read
- **Returns**: `Option<String>` — `Some(value)` if the variable exists, `None` if absent
- **Behavior**: Bypasses the 64KB WASI environment variable size limit. Reads values of arbitrary size.
- **Missing key handling**: Use `.unwrap_or_default()` to get an empty `String` when the variable is absent.

## Struct Layout

```
LargeEnvRoot  (RootContext)
  └── LargeEnvContext  (HttpContext)
```

- `LargeEnvRoot` — root context; creates `LargeEnvContext` per request
- `LargeEnvContext` — reads `LARGE_CONFIG` in `on_http_request_headers`

## Minimal Implementation Pattern

```rust
use fastedge::proxywasm::dictionary;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(LargeEnvRoot) });
}}

struct LargeEnvRoot;

impl Context for LargeEnvRoot {}

impl RootContext for LargeEnvRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(LargeEnvContext))
    }
}

struct LargeEnvContext;

impl Context for LargeEnvContext {}

impl HttpContext for LargeEnvContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        // Use dictionary::get for environment variables that may exceed 64KB.
        // For normal-sized env vars, use std::env::var() instead.
        let config = dictionary::get("LARGE_CONFIG").unwrap_or_default();

        let size = config.len();
        println!("LARGE_CONFIG size: {} bytes", size);

        self.add_http_request_header("x-config-size", &size.to_string());

        Action::Continue
    }
}
```

## Hook Usage

| Hook | Used | Purpose |
|------|------|---------|
| `on_http_request_headers` | Yes | Read large env var, forward metadata as request header |
| `on_http_response_headers` | No | — |
| `on_http_request_body` | No | — |
| `on_http_response_body` | No | — |

## Logging

```rust
println!("LARGE_CONFIG size: {} bytes", size);
```

- Uses `println!` macro for logging in the source example
- `proxy_wasm::hostcalls::log(LogLevel::Info, &msg).ok()` is also a valid logging approach; `.ok()` discards the `Result` — log failure is non-fatal

## Output Behavior

- Adds request header `x-config-size` with the byte length of `LARGE_CONFIG` as a string
- Does not modify the response
- Returns `Action::Continue` — does not block or short-circuit the request

## Constraints

- `dictionary::get` requires the `proxywasm` feature enabled on the `fastedge` crate (`fastedge = { version = "0.4", features = ["proxywasm"] }`)
- The variable must be configured as a FastEdge environment variable before deployment
- `dictionary::get` returns `None` (not an error) when the variable is absent — handle with `.unwrap_or_default()` or explicit `match`
- The WASI environment variable interface has a 64KB size limit per variable; `dictionary::get` bypasses this limit

## See Also

- fastedge-sdk-rust CDN base skeleton reference
- proxy-wasm HttpContext trait reference
- FastEdge environment variable configuration docs
- `std::env::var` (standard Rust env access for values under 64KB)

## Source Material

### FILE: examples/cdn/large_env_variable/src/lib.rs

```rust
/*
* Copyright 2025 G-Core Innovations SARL
*/
/*
Example CDN app demonstrating access to large environment variables.

Uses `fastedge::proxywasm::dictionary` to read environment variables that
may exceed the 64KB WASI environment variable size limit.

For normal-sized environment variables (< 64KB), prefer `std::env::var()`
instead. The dictionary API is only required when your variable value
may be larger than 64KB.

Required configuration:
  - Environment variable: LARGE_CONFIG (a large configuration payload, e.g. JSON)
*/

use fastedge::proxywasm::dictionary;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(LargeEnvRoot) });
}}

struct LargeEnvRoot;

impl Context for LargeEnvRoot {}

impl RootContext for LargeEnvRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(LargeEnvContext))
    }
}

struct LargeEnvContext;

impl Context for LargeEnvContext {}

impl HttpContext for LargeEnvContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        // Use dictionary::get for environment variables that may exceed 64KB.
        // For normal-sized env vars, use std::env::var() instead.
        let config = dictionary::get("LARGE_CONFIG").unwrap_or_default();

        let size = config.len();
        println!("LARGE_CONFIG size: {} bytes", size);

        self.add_http_request_header("x-config-size", &size.to_string());

        Action::Continue
    }
}
```

### FILE: examples/cdn/large_env_variable/Cargo.toml

```toml
[workspace]

[package]
name = "large_env_variable"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
fastedge = { version = "0.4", features = ["proxywasm"] }
```

### FILE: examples/cdn/large_env_variable/README.md

```
[← Back to examples](../../README.md)

# Large Environment Variable (CDN)

Demonstrates how to read **large environment variables** (> 64KB) using `fastedge::proxywasm::dictionary`.

## When to use `dictionary` vs `std::env`

| Method | Use when |
|--------|----------|
| `std::env::var("KEY")` | Variable value is under 64KB (most cases) |
| `fastedge::proxywasm::dictionary::get("KEY")` | Variable value may exceed the 64KB WASI env var size limit |

The WASI environment variable interface has a **64KB size limit** per variable. If your app needs to read larger values (e.g. large JSON configs, certificates, policy documents), use the `dictionary` API which bypasses this limit.

For all other environment variable access, prefer `std::env::var()` as it is the standard, idiomatic Rust approach.

## Required configuration

- **Environment variable**: `LARGE_CONFIG` - a large configuration payload (e.g. JSON, PEM certificate)
```
