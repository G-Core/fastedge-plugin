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
capabilities: [body-manipulation]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/body
---

# Body Manipulation — CDN App (Rust)

## When to Use

Use this pattern when you need to inspect, modify, or redact request or response bodies at the CDN layer before they reach the origin or the client.

## Dependencies

```toml
[package]
name = "body"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
log = "0.4"
proxy-wasm = "0.2"
```

## Entry Point

```rust
proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpBodyRoot) });
}}
```

## Struct Layout

```
HttpBodyRoot  — RootContext (factory)
HttpBody      — HttpContext (per-request handler)
```

## RootContext Implementation

```rust
impl RootContext for HttpBodyRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpBody))
    }
}
```

- `get_type` must return `Some(ContextType::HttpContext)` to enable HTTP lifecycle hooks.
- `create_http_context` returns a new `HttpBody` instance per request.

## HttpContext Implementation

### `on_http_request_headers`

```rust
fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
    self.set_http_request_header("content-length", None);
    Action::Continue
}
```

- Removes `content-length` from the request before body processing begins.
- Must be done before body manipulation because the body size will change.
- Returns `Action::Continue`.

### `on_http_request_body`

```rust
fn on_http_request_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
    if !end_of_stream {
        return Action::Pause;
    }

    if let Some(body_bytes) = self.get_http_request_body(0, body_size) {
        let body_str = String::from_utf8(body_bytes).unwrap();
        if body_str.contains("Client") {
            let new_body =
                format!("Client's original message body ({body_size} bytes) redacted.\n");
            self.set_http_request_body(0, body_size, &new_body.into_bytes());
        }
    }
    Action::Continue
}
```

**Body buffering pattern:**
- Return `Action::Pause` until `end_of_stream == true`. The host buffers the full body before the final call.
- Only process the body when `end_of_stream` is `true`.

**API:**

| Method | Signature | Description |
|---|---|---|
| `get_http_request_body` | `(start: usize, max_size: usize) -> Option<Vec<u8>>` | Reads buffered request body bytes |
| `set_http_request_body` | `(start: usize, size: usize, value: &[u8])` | Replaces request body bytes |

- `start`: byte offset into the body buffer (use `0` for full replacement).
- `size`: number of bytes to replace (use `body_size` for full replacement).
- Returns `Action::Continue` after modification.

### `on_http_response_headers`

```rust
fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
    self.set_http_response_header("content-length", None);
    self.set_http_response_header("transfer-encoding", Some("Chunked"));

    if let Some(content_type) = self.get_http_response_header("content-type") {
        self.set_property(vec!["response.content_type"], Some(content_type.as_bytes()));
    }

    Action::Continue
}
```

- Removes `content-length` because the response body will be modified and its size is unknown.
- Sets `transfer-encoding: Chunked` to allow streaming without a fixed content length.
- Stores `content-type` header value in a named property for use in the response body hook.

**Cross-hook state via properties:**

| Method | Signature | Description |
|---|---|---|
| `set_property` | `(path: Vec<&str>, value: Option<&[u8]>)` | Stores a value by property path |
| `get_property` | `(path: Vec<&str>) -> Option<Vec<u8>>` | Retrieves a value by property path |

- Property paths used in this example: `["response.content_type"]`, `["request.url"]`.
- Values are raw bytes; use `String::from_utf8_lossy` or `String::from_utf8` to decode.

### `on_http_response_body`

```rust
fn on_http_response_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
    if !end_of_stream {
        return Action::Pause;
    }

    let url = if let Some(value) = self.get_property(vec!["request.url"]) {
        let url = String::from_utf8_lossy(&value);
        info!("url={}", url);
        url.to_string()
    } else {
        "".to_string()
    };

    let content_type =
        if let Some(content_type) = self.get_property(vec!["response.content_type"]) {
            let content_type = String::from_utf8_lossy(&content_type);
            info!("content_type={}", content_type);
            content_type.to_string()
        } else {
            "NONE".to_string()
        };

    if let Some(body_bytes) = self.get_http_response_body(0, body_size) {
        let body_str = String::from_utf8(body_bytes).unwrap();
        if body_str.contains("Client") {
            let new_body =
                format!("Original message body ({body_size} bytes) redacted.\nURL: {url}\nContent-Type: {content_type}\n");
            self.set_http_response_body(0, body_size, &new_body.into_bytes());
        }
    }
    Action::Continue
}
```

- Same buffering pattern as request body: return `Action::Pause` until `end_of_stream == true`.
- Reads cross-hook state (`request.url`, `response.content_type`) via `get_property`.
- Logs retrieved values using `info!` macro (requires `log` crate).

**API:**

| Method | Signature | Description |
|---|---|---|
| `get_http_response_body` | `(start: usize, max_size: usize) -> Option<Vec<u8>>` | Reads buffered response body bytes |
| `set_http_response_body` | `(start: usize, size: usize, value: &[u8])` | Replaces response body bytes |

## Body Buffering Pattern (Summary)

```
on_http_request_body / on_http_response_body:
  if !end_of_stream → return Action::Pause   // wait for full body
  // full body now available in buffer
  get_http_*_body(0, body_size)              // read
  set_http_*_body(0, body_size, &new_bytes)  // write
  return Action::Continue
```

The host accumulates body chunks internally. The hook is called repeatedly until `end_of_stream` is `true`, at which point the complete body is available in one call to `get_http_*_body`.

## Header / Property Coordination Pattern

When body size changes across hooks:

1. **Request headers hook**: remove `content-length` before the body arrives.
2. **Response headers hook**: remove `content-length`, set `transfer-encoding: Chunked`, snapshot headers needed later via `set_property`.
3. **Body hooks**: read snapshots via `get_property`, modify body, return `Action::Continue`.

## Constraints

- `String::from_utf8(body_bytes).unwrap()` — panics if body is not valid UTF-8. Use `from_utf8_lossy` for non-UTF-8 safe handling.
- `get_http_request_body` / `get_http_response_body` return `None` if the body buffer is empty or unavailable.
- Body manipulation is only valid after `end_of_stream == true`.
- Removing `content-length` is required before changing body size; failure to do so may cause protocol errors.

## Logging

```rust
use log::info;
// ...
info!("url={}", url);
info!("content_type={}", content_type);
```

Requires `log = "0.4"` in `Cargo.toml`. Log level is set to `Trace` at startup via `proxy_wasm::set_log_level(LogLevel::Trace)`.

## See Also

- cdn-base skeleton reference
- proxy-wasm HttpContext trait reference
- host-services-rust reference (property API, logging)
- platform-overview reference (CDN app lifecycle)
