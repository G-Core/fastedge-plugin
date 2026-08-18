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
capabilities: [custom-response, path-routing, early-response]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/custom
---

# CDN Feature: Custom Response (Rust)

## When to Use

Use this feature when you want to return custom HTTP responses (specific status codes, optional delays) directly from the CDN edge based on request path, without forwarding to origin. Suitable for testing, mocking, health-check endpoints, or simulating network conditions.

## Cargo.toml

```toml
[workspace]

[package]
name = "custom"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
log = "0.4"
proxy-wasm = "0.2"
```

## Full Example

```rust
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::time::Duration;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpHeadersRoot) });
}}

const BAD_REQUEST: u32 = 400;

struct HttpHeadersRoot;

impl Context for HttpHeadersRoot {}

impl RootContext for HttpHeadersRoot {
    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpHeaders))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct HttpHeaders;

impl Context for HttpHeaders {}

impl HttpContext for HttpHeaders {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let Some(path) = self.get_property(vec!["request.path"]) else {
            self.send_http_response(BAD_REQUEST, vec![], Some(b"Malformed request - no path"));
            return Action::Pause;
        };

        let Ok(path) = std::str::from_utf8(&path) else {
            self.send_http_response(
                BAD_REQUEST,
                vec![],
                Some(b"Malformed request - not utf8 string"),
            );
            return Action::Pause;
        };

        // Trim leading '/'
        let path = if path.starts_with('/') {
            &path[1..]
        } else {
            path
        };
        let mut segments = path.split('/');

        let Some(status_code) = segments.next() else {
            return Action::Continue;
        };

        if let Some(delay) = segments.next() {
            if let Ok(delay) = delay.parse::<u64>() {
                std::thread::sleep(Duration::from_millis(delay));
            }
        }

        let Ok(status_code) = status_code.parse::<u32>() else {
            self.send_http_response(
                BAD_REQUEST,
                vec![],
                Some(b"Malformed request - invalid status code"),
            );
            return Action::Pause;
        };

        match status_code {
            0 | 200 => Action::Continue,
            code if code < 600 => {
                self.send_http_response(code, vec![], None);
                Action::Pause
            }
            _ => {
                self.send_http_response(BAD_REQUEST, vec![], None);
                Action::Pause
            }
        }
    }
}
```

## Key Patterns

### Path-Based Response Dispatch

Request path encodes the desired status code and optional delay:

```
/<status_code>[/<delay_ms>]
```

- First segment: HTTP status code to return (integer, 1–599)
- Second segment (optional): delay in milliseconds before responding

Example paths:
- `/404` — return 404 immediately
- `/503/2000` — return 503 after a 2000 ms delay
- `/200` or `/0` — pass through to origin (`Action::Continue`)

### Property Retrieval

```rust
let Some(path) = self.get_property(vec!["request.path"]) else {
    self.send_http_response(BAD_REQUEST, vec![], Some(b"Malformed request - no path"));
    return Action::Pause;
};
```

- `get_property(vec!["request.path"])` — retrieves the raw request path as `Option<Vec<u8>>`
- Returns `None` if path is absent; respond with 400 and `Action::Pause`

### UTF-8 Decoding

```rust
let Ok(path) = std::str::from_utf8(&path) else {
    self.send_http_response(
        BAD_REQUEST,
        vec![],
        Some(b"Malformed request - not utf8 string"),
    );
    return Action::Pause;
};
```

- Decode raw bytes to `&str`; on failure respond with 400 and `Action::Pause`

### Leading Slash Trim

```rust
let path = if path.starts_with('/') { &path[1..] } else { path };
```

- Strips leading `/` before splitting into segments

### Artificial Delay

```rust
if let Some(delay) = segments.next() {
    if let Ok(delay) = delay.parse::<u64>() {
        std::thread::sleep(Duration::from_millis(delay));
    }
}
```

- Parses second path segment as `u64` milliseconds
- Non-numeric values are silently ignored (no error response)
- Uses `std::thread::sleep` — blocks the WASM thread for the specified duration

### Synthetic Response (Early Return)

```rust
self.send_http_response(code, vec![], None);
Action::Pause
```

- `send_http_response(status, headers, body)` — sends an HTTP response directly from the edge
- `vec![]` — no additional headers
- `None` — no response body (use `Some(b"...")` to include a body)
- `Action::Pause` — stops pipeline; upstream (origin) is NOT contacted

### Pass-Through

```rust
0 | 200 => Action::Continue,
```

- `Action::Continue` — request proceeds to origin unchanged

### Status Code Dispatch

| Status code value | Behavior |
|---|---|
| `0` or `200` | `Action::Continue` — pass to origin |
| `1`–`599` (except 200) | `send_http_response(code, ...)` + `Action::Pause` |
| `600`+ | `send_http_response(400, ...)` + `Action::Pause` |
| Non-numeric | `send_http_response(400, ...)` + `Action::Pause` |
| Path absent | `send_http_response(400, ...)` + `Action::Pause` |
| Path not UTF-8 | `send_http_response(400, ...)` + `Action::Pause` |

## Error Conditions

| Condition | Response | Body |
|---|---|---|
| `request.path` property absent | 400 | `"Malformed request - no path"` |
| Path bytes not valid UTF-8 | 400 | `"Malformed request - not utf8 string"` |
| First segment not a valid `u32` | 400 | `"Malformed request - invalid status code"` |
| Status code >= 600 | 400 | (none) |

## Trait Implementations Required

| Trait | Implemented On | Purpose |
|---|---|---|
| `Context` | `HttpHeadersRoot` | Required by proxy-wasm for all context types |
| `RootContext` | `HttpHeadersRoot` | Entry point; factory for per-request `HttpContext` |
| `Context` | `HttpHeaders` | Required by proxy-wasm for all context types |
| `HttpContext` | `HttpHeaders` | Per-request handler; `on_http_request_headers` hook |

## Dependencies

| Crate | Version | Purpose |
|---|---|---|
| `proxy-wasm` | `0.2` | CDN WASM host ABI — traits, types, `Action`, `send_http_response` |
| `log` | `0.4` | Logging facade (available for use; not exercised in this example) |
| `std::time::Duration` | stdlib | Delay argument construction for `thread::sleep` |

## See Also

- cdn-base skeleton reference
- host-services-rust reference (property access, send_http_response ABI details)
- sdk-reference-rust reference (proxy-wasm trait hierarchy)
- best-practices reference (error handling patterns, Action semantics)

## Source Material

### FILE: examples/cdn/custom/src/lib.rs

```rust
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::time::Duration;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpHeadersRoot) });
}}

const BAD_REQUEST: u32 = 400;

struct HttpHeadersRoot;

impl Context for HttpHeadersRoot {}

impl RootContext for HttpHeadersRoot {
    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpHeaders))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct HttpHeaders;

impl Context for HttpHeaders {}

impl HttpContext for HttpHeaders {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let Some(path) = self.get_property(vec!["request.path"]) else {
            self.send_http_response(BAD_REQUEST, vec![], Some(b"Malformed request - no path"));
            return Action::Pause;
        };

        let Ok(path) = std::str::from_utf8(&path) else {
            self.send_http_response(
                BAD_REQUEST,
                vec![],
                Some(b"Malformed request - not utf8 string"),
            );
            return Action::Pause;
        };

        //trim first '/'
        let path = if path.starts_with('/') {
            &path[1..]
        } else {
            path
        };
        let mut segments = path.split('/');

        let Some(status_code) = segments.next() else {
            return Action::Continue;
        };

        if let Some(delay) = segments.next() {
            if let Ok(delay) = delay.parse::<u64>() {
                std::thread::sleep(Duration::from_millis(delay));
            }
        }

        let Ok(status_code) = status_code.parse::<u32>() else {
            self.send_http_response(
                BAD_REQUEST,
                vec![],
                Some(b"Malformed request - invalid status code"),
            );
            return Action::Pause;
        };

        match status_code {
            0 | 200 => Action::Continue,
            code if code < 600 => {
                self.send_http_response(code, vec![], None);
                Action::Pause
            }
            _ => {
                self.send_http_response(BAD_REQUEST, vec![], None);
                Action::Pause
            }
        }
    }
}
```

### FILE: examples/cdn/custom/Cargo.toml

```toml
[workspace]

[package]
name = "custom"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
log = "0.4"
proxy-wasm = "0.2"
```

### FILE: examples/cdn/custom/README.md

```
[← Back to examples](../../README.md)

# Custom (CDN)

Returns HTTP status codes based on the request path, with optional delay support. Useful for testing and debugging CDN behaviour.
```
