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
capabilities: [http-call, async-dispatch]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/http_call
---

# HTTP Call — CDN (Rust)

Makes asynchronous outbound HTTP calls to external services with timeout handling from a CDN filter, using the proxy-wasm ABI.

## When to Use

Use this blueprint when the CDN filter must make an outbound HTTP request to an external service before continuing or modifying the original request/response.

## Dependencies

```toml
[dependencies]
log = "0.4"
proxy-wasm = "0.2"
```

Crate type must be `cdylib`.

## Imports

```rust
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::time::Duration;
```

`std::time::Duration` must be imported explicitly — it is not covered by the proxy-wasm glob imports.

## Struct Layout

```rust
struct HttpHeadersRoot;          // RootContext — creates per-request contexts

struct HttpHeaders {
    state: u32,                  // 0 = initial, 1 = HTTP call response received
}
```

## Entry Point

```rust
proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpHeadersRoot) });
}}
```

## RootContext Implementation

```rust
impl Context for HttpHeadersRoot {}

impl RootContext for HttpHeadersRoot {
    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpHeaders { state: 0 }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}
```

## Async Dispatch Pattern

### Dispatching the HTTP Call

Called in `on_http_request_headers`. Returns `Action::Pause` to suspend the original request until the callback fires.

```rust
impl HttpContext for HttpHeaders {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        println!("state: {}", self.state);

        if self.state == 1 {
            println!("HTTP call response was received successfully, resuming request.");
            return Action::Continue;
        }

        match self.dispatch_http_call(
            "httpbin.org",
            vec![
                (":scheme", "https"),
                (":authority", "httpbin.org"),
                (":path", "/ip"),
                ("User-Agent", "fastedge"),
            ],
            Some("body".as_bytes()),
            vec![],
            Duration::from_millis(1000),
        ) {
            Ok(token_id) => {
                println!("Dispatched http call with token id: {token_id}");
                Action::Pause
            }
            Err(status) => {
                self.send_http_response(
                    to_status_code(status),
                    vec![],
                    Some(format!("Failed to dispatch http call: {:?}", status).as_bytes()),
                );
                Action::Pause
            }
        }
    }
}
```

#### `dispatch_http_call` Signature

```
self.dispatch_http_call(
    upstream: &str,
    headers: Vec<(&str, &str)>,
    body: Option<&[u8]>,
    trailers: Vec<(&str, &str)>,
    timeout: Duration,
) -> Result<u32, Status>
```

| Parameter  | Type                   | Notes |
|------------|------------------------|-------|
| `upstream` | `&str`                 | Name of the upstream cluster configured in the host |
| `headers`  | `Vec<(&str, &str)>`    | Must include pseudo-headers `:scheme`, `:authority`, `:path`; additional headers optional |
| `body`     | `Option<&[u8]>`        | Optional request body bytes; pass `None` if unused |
| `trailers` | `Vec<(&str, &str)>`    | HTTP trailers; pass `vec![]` if unused |
| `timeout`  | `Duration`             | Maximum wait duration; use `Duration::from_millis(n)` |

Returns `Ok(token_id)` on success; `token_id` matches the value passed to `on_http_call_response`. Returns `Err(Status)` on failure.

### Receiving the Response (Callback)

Implemented on `Context` (not `HttpContext`).

```rust
impl Context for HttpHeaders {
    fn on_http_call_response(
        &mut self,
        token_id: u32,
        num_headers: usize,
        _body_size: usize,
        _num_trailers: usize,
    ) {
        println!(
            "Received http call response with token id: {token_id}, num_headers: {num_headers}"
        );
        // If num_headers is 0, then the HTTP call failed.
        if num_headers != 0 {
            let headers = self.get_http_call_response_headers();
            let headers_str = headers
                .iter()
                .map(|(name, value)| format!("\"{}: {}\"", name, value))
                .collect::<Vec<_>>()
                .join(",");
            println!("Response headers: [{}]", headers_str);

            self.state = 1; // Set state to 1 to indicate that the HTTP call response was received successfully.

            self.resume_http_request();
        } else {
            self.reset_http_request();
        }
    }
}
```

#### Callback Parameters

| Parameter      | Type    | Meaning                                               |
|----------------|---------|-------------------------------------------------------|
| `token_id`     | `u32`   | Matches the `Ok(token_id)` from `dispatch_http_call` |
| `num_headers`  | `usize` | Number of response headers; `0` means call failed    |
| `body_size`    | `usize` | Size of response body in bytes                        |
| `num_trailers` | `usize` | Number of response trailers                           |

#### Response Reading APIs

| Method | Returns | Notes |
|--------|---------|-------|
| `self.get_http_call_response_header(name)` | `Option<String>` | Single header by name |
| `self.get_http_call_response_headers()` | `Vec<(String, String)>` | All headers as strings |
| `self.get_http_call_response_headers_bytes()` | `Vec<(String, Vec<u8>)>` | All headers as bytes |
| `self.get_http_call_response_body(start, size)` | `Option<Bytes>` | Body slice; pass `(0, body_size)` for full body |

### Resuming or Resetting the Original Request

| Method | Use case |
|--------|----------|
| `self.resume_http_request()` | HTTP call succeeded — continue processing the original request |
| `self.resume_http_response()` | Alternative: continue processing the original response instead |
| `self.reset_http_request()` | HTTP call failed (`num_headers == 0`) — abort/reset the original request |

## State Tracking

Use a struct field to distinguish the initial pass from the resumed pass:

```rust
struct HttpHeaders {
    state: u32, // 0 = first pass, 1 = HTTP call complete
}
```

In `on_http_request_headers`, check `self.state == 1` before dispatching to avoid re-dispatching on the resumed request.

## Status to HTTP Status Code Mapping

```rust
fn to_status_code(status: Status) -> u32 {
    match status {
        Status::Ok                   => 200,
        Status::NotFound             => 404,
        Status::BadArgument          => 400,
        Status::SerializationFailure => 500,
        Status::ParseFailure         => 400,
        Status::Empty                => 204,
        Status::CasMismatch          => 409,
        Status::InternalFailure      => 500,
        _                            => 500,
    }
}
```

## Control Flow Summary

```
on_http_request_headers (state == 0)
  → dispatch_http_call() → Action::Pause

on_http_call_response (num_headers > 0)
  → read headers / body
  → state = 1
  → resume_http_request()

on_http_request_headers (state == 1)
  → Action::Continue

on_http_call_response (num_headers == 0)  [failure path]
  → reset_http_request()
```

## See Also

- cdn-base skeleton reference
- FastEdge-sdk-rust proxy-wasm traits documentation
- host-services-rust reference (upstream cluster configuration)
- scaffold skill cdn blueprint index

## Source Material

### FILE: examples/cdn/http_call/src/lib.rs

```rust
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::time::Duration;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpHeadersRoot) });
}}

struct HttpHeadersRoot;

impl Context for HttpHeadersRoot {}

impl RootContext for HttpHeadersRoot {
    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpHeaders { state: 0 }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct HttpHeaders {
    state: u32,
}

impl Context for HttpHeaders {
    fn on_http_call_response(
        &mut self,
        token_id: u32,
        num_headers: usize,
        _body_size: usize,
        _num_trailers: usize,
    ) {
        println!(
            "Received http call response with token id: {token_id}, num_headers: {num_headers}"
        );
        //If num_headers is 0, then the HTTP call failed.
        if num_headers != 0 {
            let headers = self.get_http_call_response_headers();
            let headers_str = headers
                .iter()
                .map(|(name, value)| format!("\"{}: {}\"", name, value))
                .collect::<Vec<_>>()
                .join(",");
            println!("Response headers: [{}]", headers_str);

            self.state = 1; // Set state to 1 to indicate that the HTTP call response was received successfully.

            self.resume_http_request();
        } else {
            self.reset_http_request();
        }
    }
}

impl HttpContext for HttpHeaders {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        println!("state: {}", self.state);

        if self.state == 1 {
            println!("HTTP call response was received successfully, resuming request.");
            return Action::Continue;
        }

        match self.dispatch_http_call(
            "httpbin.org",
            vec![
                (":scheme", "https"),
                (":authority", "httpbin.org"),
                (":path", "/ip"),
                ("User-Agent", "fastedge"),
            ],
            Some("body".as_bytes()),
            vec![],
            Duration::from_millis(1000),
        ) {
            Ok(token_id) => {
                println!("Dispatched http call with token id: {token_id}");
                Action::Pause
            }
            Err(status) => {
                self.send_http_response(
                    to_status_code(status),
                    vec![],
                    Some(format!("Failed to dispatch http call: {:?}", status).as_bytes()),
                );
                Action::Pause
            }
        }
    }
}

fn to_status_code(status: Status) -> u32 {
    match status {
        Status::Ok => 200,
        Status::NotFound => 404,
        Status::BadArgument => 400,
        Status::SerializationFailure => 500,
        Status::ParseFailure => 400,
        Status::Empty => 204,
        Status::CasMismatch => 409,
        Status::InternalFailure => 500,
        _ => 500,
    }
}
```

### FILE: examples/cdn/http_call/Cargo.toml

```toml
[workspace]

[package]
name = "http_call"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
log = "0.4"
proxy-wasm = "0.2"
```

### FILE: examples/cdn/http_call/README.md

```
[← Back to examples](../../README.md)

# HTTP Call (CDN)

Makes asynchronous HTTP calls to external services with timeout handling using the proxy-wasm ABI.
```
