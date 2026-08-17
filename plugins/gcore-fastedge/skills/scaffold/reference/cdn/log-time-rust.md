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
capabilities: [logging, timing, observability]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/log_time
---

# Log Time — CDN Feature Blueprint (Rust)

## Purpose

Demonstrates how to log request and response timestamps (hours since UNIX epoch) using `self.get_current_time()` and the `log` crate in a CDN app. Use this blueprint when you need to add timing or observability logging to request and response phases, or need a minimal working example of `get_current_time()` with structured logging.

## When to Use

- Adding timing or observability logging to request and/or response phases of a CDN app
- Demonstrating or debugging `get_current_time()` in the proxy-wasm context
- Replacing `println!`-based logging with structured `log::info!` macros and log-level control

## Dependencies

```toml
[dependencies]
log = "0.4"
proxy-wasm = "0.2"
```

Crate type must be `cdylib`:

```toml
[lib]
crate-type = ["cdylib"]
```

## Full Implementation

```rust
use log::info;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::time::SystemTime;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpHeadersRoot) });
}}

struct HttpHeadersRoot;

impl Context for HttpHeadersRoot {}

impl RootContext for HttpHeadersRoot {
    fn create_http_context(&self, context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpHeaders { context_id }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct HttpHeaders {
    context_id: u32,
}

impl Context for HttpHeaders {}

impl HttpContext for HttpHeaders {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let time = self.get_current_time();
        info!(
            "on_http_request_headers: {}",
            time.duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs()
                / 3600
        );
        Action::Continue
    }

    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        let time = self.get_current_time();
        info!(
            "on_http_response_headers: {}",
            time.duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs()
                / 3600
        );
        Action::Continue
    }
}
```

## Key Patterns

### Structured Logging Setup

Set log level in `proxy_wasm::main!` before registering the root context:

```rust
proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpHeadersRoot) });
}}
```

`LogLevel::Trace` enables all log output. Use `log::info!`, `log::warn!`, `log::error!` macros from the `log` crate — this is the recommended approach for CDN apps rather than `println!`.

### Passing `context_id` Through Hook Lifecycle

The `context_id: u32` field is populated via `create_http_context` and carried on the `HttpHeaders` struct. This allows correlation of log entries across hooks for the same request:

```rust
fn create_http_context(&self, context_id: u32) -> Option<Box<dyn HttpContext>> {
    Some(Box::new(HttpHeaders { context_id }))
}
```

The `context_id` field is available throughout all `HttpContext` hook methods on the same struct instance.

### Getting Current Time

`self.get_current_time()` is provided by the `Context` trait via proxy-wasm. It returns a `SystemTime`:

```rust
let time = self.get_current_time();
```

### Time-to-Hours Computation

Convert `SystemTime` to hours since UNIX epoch:

```rust
time.duration_since(SystemTime::UNIX_EPOCH)
    .unwrap()
    .as_secs()
    / 3600
```

- `duration_since(SystemTime::UNIX_EPOCH)` — returns `Result<Duration, SystemTimeError>`
- `.unwrap()` — safe here because proxy-wasm time is always after the epoch
- `.as_secs()` — total seconds as `u64`
- `/ 3600` — integer division to hours

### Hook Return Value

Both hooks return `Action::Continue`, which passes the request/response through without modification. This feature adds observability only — it does not alter headers or body.

## Struct Summary

| Struct | Traits Implemented | Purpose |
|---|---|---|
| `HttpHeadersRoot` | `Context`, `RootContext` | Factory; registers log level; creates per-request contexts |
| `HttpHeaders` | `Context`, `HttpContext` | Per-request handler; logs timestamps on request and response |

## Hook Reference

| Hook | Trigger | Return |
|---|---|---|
| `on_http_request_headers` | Incoming request headers received | `Action::Continue` |
| `on_http_response_headers` | Upstream response headers received | `Action::Continue` |

## Constraints

- `get_current_time()` is only available within a `Context` implementation — it is a proxy-wasm host function, not a standard Rust call.
- `LogLevel::Trace` must be set before any log macros are invoked; placement in `proxy_wasm::main!` ensures this.
- The `log` crate macros (`info!`, etc.) route through the proxy-wasm host logger — output destination depends on the FastEdge runtime configuration.
- Integer division `/ 3600` truncates sub-hour precision; use `.as_millis()` or `.as_nanos()` for finer granularity if needed.

## See Also

- cdn-base skeleton reference (base struct layout, `proxy_wasm::main!` setup, `Action` enum)
- platform-overview reference (CDN app lifecycle, hook execution order)
- host-services-rust reference (`get_current_time`, `Context` trait, `LogLevel` variants)
- best-practices reference (log level selection, structured logging conventions)

## Source Material

### FILE: examples/cdn/log_time/src/lib.rs

```rust
use log::info;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::time::SystemTime;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpHeadersRoot) });
}}

struct HttpHeadersRoot;

impl Context for HttpHeadersRoot {}

impl RootContext for HttpHeadersRoot {
    fn create_http_context(&self, context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpHeaders { context_id }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct HttpHeaders {
    context_id: u32,
}

impl Context for HttpHeaders {}

impl HttpContext for HttpHeaders {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let time = self.get_current_time();
        info!(
            "on_http_request_headers: {}",
            time.duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs()
                / 3600
        );
        Action::Continue
    }

    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        let time = self.get_current_time();
        info!(
            "on_http_response_headers: {}",
            time.duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs()
                / 3600
        );
        Action::Continue
    }
}
```

### FILE: examples/cdn/log_time/Cargo.toml

```toml
[workspace]

[package]
name = "log_time"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
log = "0.4"
proxy-wasm = "0.2"
```

### FILE: examples/cdn/log_time/README.md

```
[← Back to examples](../../README.md)

# Log Time (CDN)

Logs request and response timestamps (hours since UNIX epoch) using the proxy-wasm ABI.
```
