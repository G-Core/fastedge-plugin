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
capabilities: [header-manipulation]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/headers
---

# Header Manipulation — CDN (Rust)

Validates and manipulates HTTP request and response headers using the proxy-wasm ABI. Covers both request-phase and response-phase header operations: read, add, replace, and remove headers by string value or raw bytes.

## When to Use

Use this feature when you need to add, remove, replace, or inspect HTTP request and response headers at the CDN layer before forwarding to origin or before returning to the client.

## Cargo.toml

```toml
[package]
name = "headers"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
```

## Struct Layout

```rust
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::collections::HashSet;

struct HttpHeadersRoot;
struct HttpHeaders {
    context_id: u32,
}
```

## Entrypoint

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
    fn create_http_context(&self, context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpHeaders { context_id }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}
```

## HttpContext Implementation

Implement `Context` and `HttpContext` for `HttpHeaders`. Override `on_http_request_headers` and/or `on_http_response_headers` to manipulate headers at the respective phase.

```rust
impl Context for HttpHeaders {}

impl HttpContext for HttpHeaders {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action { ... }
    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action { ... }
    fn on_log(&mut self) { ... }
}
```

---

## API Reference

### Request Header Methods

All methods are called on `self` within `HttpContext`.

| Method | Signature | Returns | Notes |
|---|---|---|---|
| `get_http_request_headers` | `() -> Vec<(String, String)>` | All request headers as string pairs | Includes duplicates |
| `get_http_request_headers_bytes` | `() -> Vec<(String, Bytes)>` | All request headers as byte pairs | Includes duplicates |
| `get_http_request_header` | `(name: &str) -> Option<String>` | First matching header value or `None` | Case-insensitive name |
| `get_http_request_header_bytes` | `(name: &str) -> Option<Bytes>` | First matching header value as bytes or `None` | Case-insensitive name |
| `add_http_request_header` | `(name: &str, value: &str)` | `()` | Appends; allows duplicate names |
| `add_http_request_header_bytes` | `(name: &str, value: &[u8])` | `()` | Appends bytes; allows duplicate names |
| `set_http_request_header` | `(name: &str, value: Option<&str>)` | `()` | `Some(v)` replaces all entries for that name; `None` removes (see caveat) |
| `set_http_request_header_bytes` | `(name: &str, value: Option<&[u8]>)` | `()` | `Some(v)` replaces; `None` removes (see caveat) |

### Response Header Methods

Available in both `on_http_request_headers` (limited) and `on_http_response_headers` (full access).

| Method | Signature | Returns | Notes |
|---|---|---|---|
| `get_http_response_headers` | `() -> Vec<(String, String)>` | All response headers as string pairs | |
| `get_http_response_headers_bytes` | `() -> Vec<(String, Bytes)>` | All response headers as byte pairs | |
| `get_http_response_header` | `(name: &str) -> Option<String>` | First matching response header or `None` | |
| `get_http_response_header_bytes` | `(name: &str) -> Option<Bytes>` | First matching response header bytes or `None` | |
| `add_http_response_header` | `(name: &str, value: &str)` | `()` | Appends; allows duplicate names |
| `add_http_response_header_bytes` | `(name: &str, value: &[u8])` | `()` | Appends bytes; allows duplicate names |
| `set_http_response_header` | `(name: &str, value: Option<&str>)` | `()` | `Some(v)` replaces all entries for that name; `None` removes (see caveat) |
| `set_http_response_header_bytes` | `(name: &str, value: Option<&[u8]>)` | `()` | `Some(v)` replaces; `None` removes (see caveat) |

---

## Platform Caveat: Header Removal

`set_http_request_header(name, None)` and `set_http_response_header(name, None)` (and their `_bytes` variants) are the intended removal API. On the FastEdge platform, removing a header sets its value to an empty string rather than truly removing the header entry. When checking for header absence after removal, test for both `None` and empty string:

```rust
match self.get_http_request_header("some-header") {
    None | Some(ref v) if v.is_empty() => { /* treated as absent */ }
    Some(v) => { /* header present with value */ }
}
```

---

## Usage Patterns

### Read All Request Headers

```rust
fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
    for (name, value) in self.get_http_request_headers() {
        println!("#{} -> {}: {}", self.context_id, name, value);
    }
    Action::Continue
}
```

### Check for a Specific Header

```rust
if self.get_http_request_header("host").is_none() {
    self.send_http_response(400, vec![], None);
    return Action::Pause;
}
```

### Add Headers (Allows Duplicates)

```rust
self.add_http_request_header("x-custom", "value-a");
self.add_http_request_header("x-custom", "value-b"); // duplicate allowed
self.add_http_request_header_bytes("x-raw", b"raw-value");
```

### Replace a Header Value

```rust
self.set_http_request_header("x-custom", Some("replacement-value"));
self.set_http_request_header_bytes("x-raw", Some(b"new-raw-value"));
```

### Remove a Header

```rust
self.set_http_request_header("x-custom", None);       // sets to empty string on platform
self.set_http_request_header_bytes("x-raw", None);    // sets to empty bytes on platform
```

### Manipulate Response Headers in Request Phase

Response header methods are callable during `on_http_request_headers`, but only headers set at this phase are visible — full upstream response headers are not yet available:

```rust
fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
    self.add_http_response_header("new-response-header", "value-01");
    self.set_http_response_header("cache-control", None);
    self.set_http_response_header("new-response-header", Some("value-02"));
    // get_http_response_header returns only headers set in this phase
    Action::Continue
}
```

### Validate Response Headers Set in Request Phase

After setting response headers in the request phase, `get_http_response_headers()` returns exactly the headers set in that phase. `get_http_response_header("host")` returns `None` because upstream response headers are not yet available:

```rust
// After add + set in on_http_request_headers:
// get_http_response_headers() returns exactly 1 entry: ("new-response-header", "value-02")
let response_headers = self.get_http_response_headers();
if response_headers.len() != 1 {
    self.send_http_response(555, vec![], None);
    return Action::Pause;
}
let Some((name, value)) = response_headers.into_iter().next() else {
    self.send_http_response(555, vec![], None);
    return Action::Pause;
};
if name != "new-response-header" || value != "value-02" {
    self.send_http_response(556, vec![], None);
    return Action::Pause;
}
```

### Manipulate Response Headers in Response Phase

```rust
fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
    for (name, value) in self.get_http_response_headers().into_iter() {
        println!("#{} -> {}: {}", self.context_id, name, value);
    }
    self.add_http_response_header("new-header-01", "value-01");
    self.add_http_response_header_bytes("new-header-bytes-01", b"value-bytes-01");
    self.set_http_response_header("new-header-01", None);       // sets to empty string
    self.set_http_response_header("new-header-02", Some("new-value-02"));
    self.add_http_response_header("new-header-03", "value-03-a"); // duplicate allowed
    Action::Continue
}
```

### Verify Header Diffs After Manipulation

The source example tracks original headers in a `HashSet` and computes the diff against expected entries after manipulation. This pattern confirms that `set_*(name, None)` results in an empty-string entry (not removal), and `add_*` with a duplicate name appends rather than replaces:

```rust
let headers = self.get_http_request_headers()
    .into_iter()
    .collect::<HashSet<(String, String)>>();

// After add/set operations, expected new entries include:
// ("new-header-01", "")                          // removed → empty string
// ("new-header-bytes-01", "")                    // removed → empty string
// ("new-header-02", "new-value-02")              // replaced
// ("new-header-bytes-02", "new-value-bytes-02")  // replaced
// ("new-header-03", "value-03")                  // original add
// ("new-header-bytes-03", "value-bytes-03")      // original add
// ("new-header-03", "value-03-a")                // duplicate add preserved
// ("new-header-bytes-03", "value-bytes-03-a")    // duplicate add preserved

let diff = headers
    .difference(&original_headers)
    .collect::<HashSet<_>>();
let diff = diff.difference(&expected).collect::<Vec<_>>();
if !diff.is_empty() {
    self.send_http_response(552, vec![], None);
    return Action::Pause;
}
```

The same diff pattern applies to bytes variants using `get_http_request_headers_bytes()` and a `HashSet<(String, Bytes)>`. The response phase (`on_http_response_headers`) applies an identical add/set/diff sequence using response header methods.

---

## Error Handling

Use `send_http_response` to short-circuit the request with a synthetic response and `Action::Pause` to stop further processing:

```rust
self.send_http_response(400, vec![], None);
return Action::Pause;
```

Return `Action::Continue` when processing should proceed normally.

---

## Error Codes Used in Example

| Code | Meaning |
|---|---|
| 550 | No headers found (request or response headers collection is empty) |
| 551 | Required `host` header is absent |
| 552 | Unexpected header diff after manipulation |
| 553 | Expected response header missing (`host` header visible in response phase from request phase) |
| 554 | Response header value unexpectedly non-empty |
| 555 | Response header count mismatch |
| 556 | Response header name/value mismatch |

---

## Lifecycle Hook

```rust
fn on_log(&mut self) {
    println!("#{} completed.", self.context_id);
}
```

Called after the request/response cycle completes. Use for per-request logging or cleanup.

---

## Constraints

- `add_http_request_header` / `add_http_response_header` append new entries; existing entries with the same name are preserved (duplicates allowed).
- `set_http_request_header` / `set_http_response_header` with `Some(value)` replaces all existing entries for that name.
- `set_*` with `None` performs removal, but the FastEdge platform retains the entry with an empty value.
- Response headers accessed during `on_http_request_headers` reflect only headers set within that same phase — upstream response headers are not yet available.
- Full upstream response headers are only accessible in `on_http_response_headers`.
- `get_http_response_header("host")` returns `None` during `on_http_request_headers` because the upstream response has not been received yet.
- After `set_*(name, None)`, `get_*` returns `Some("")` (empty string) rather than `None` on the FastEdge platform.
- Both string and bytes variants (`_bytes` suffix) are available for all read, add, and set operations; behavior is identical except for the value type (`&str`/`String` vs `&[u8]`/`Bytes`).

---

## See Also

- cdn-base skeleton (cdn-base)
- proxy-wasm Rust SDK reference (sdk-reference-rust)
- FastEdge CDN app examples index (examples CDN)
- Host services Rust reference (host-services-rust)

## Source Material

### FILE: examples/cdn/headers/src/lib.rs

```rust
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::collections::HashSet;

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
        let mut original_headers = HashSet::new();
        let mut original_headers_bytes = HashSet::new();

        // iterate over the headers and print them
        for (name, value) in self.get_http_request_headers().into_iter() {
            println!("#{} -> {}: {}", self.context_id, name, value);
            original_headers.insert((name, value));
        }
        for (name, value) in self.get_http_request_headers_bytes().into_iter() {
            println!("#{} -> {}: {:?}", self.context_id, name, value);
            original_headers_bytes.insert((name, value));
        }
        if original_headers.is_empty() || original_headers_bytes.is_empty() {
            self.send_http_response(550, vec![], None);
            return Action::Pause;
        }

        // check if the host header is present
        if self.get_http_request_header("host").is_none() {
            self.send_http_response(551, vec![], None);
            return Action::Pause;
        }
        if self.get_http_request_header_bytes("host").is_none() {
            self.send_http_response(551, vec![], None);
            return Action::Pause;
        }

        // add new headers
        self.add_http_request_header("new-header-01", "value-01");
        self.add_http_request_header_bytes("new-header-bytes-01", b"value-bytes-01");

        self.add_http_request_header("new-header-02", "value-02");
        self.add_http_request_header_bytes("new-header-bytes-02", b"value-bytes-02");

        self.add_http_request_header("new-header-03", "value-03");
        self.add_http_request_header_bytes("new-header-bytes-03", b"value-bytes-03");

        //remove header new-headter-01, expected empty value
        self.set_http_request_header("new-header-01", None);
        self.set_http_request_header_bytes("new-header-bytes-01", None);

        // changing header value
        self.set_http_request_header("new-header-02", Some("new-value-02"));
        self.set_http_request_header_bytes("new-header-bytes-02", Some(b"new-value-bytes-02"));

        // add new header with existing name
        self.add_http_request_header("new-header-03", "value-03-a");
        self.add_http_request_header_bytes("new-header-bytes-03", b"value-bytes-03-a");

        // try to set/add response headers
        self.add_http_response_header("new-response-header", "value-01");
        self.set_http_response_header("cache-control", None);
        self.set_http_response_header("new-response-header", Some("value-02"));

        // get new headers
        let headers = self
            .get_http_request_headers()
            .into_iter()
            .collect::<HashSet<(String, String)>>();
        let headers_bytes = self
            .get_http_request_headers_bytes()
            .into_iter()
            .collect::<HashSet<(String, Bytes)>>();

        let expected = [
            ("new-header-01".to_string(), "".to_string()),
            ("new-header-bytes-01".to_string(), "".to_string()),
            ("new-header-02".to_string(), "new-value-02".to_string()),
            (
                "new-header-bytes-02".to_string(),
                "new-value-bytes-02".to_string(),
            ),
            ("new-header-03".to_string(), "value-03".to_string()),
            (
                "new-header-bytes-03".to_string(),
                "value-bytes-03".to_string(),
            ),
            ("new-header-03".to_string(), "value-03-a".to_string()),
            (
                "new-header-bytes-03".to_string(),
                "value-bytes-03-a".to_string(),
            ),
        ];

        let expected = expected.iter().collect::<HashSet<_>>();

        let expected_bytes = [
            ("new-header-01".to_string(), b"".to_vec()),
            ("new-header-bytes-01".to_string(), b"".to_vec()),
            ("new-header-02".to_string(), b"new-value-02".to_vec()),
            (
                "new-header-bytes-02".to_string(),
                b"new-value-bytes-02".to_vec(),
            ),
            ("new-header-03".to_string(), b"value-03".to_vec()),
            (
                "new-header-bytes-03".to_string(),
                b"value-bytes-03".to_vec(),
            ),
            ("new-header-03".to_string(), b"value-03-a".to_vec()),
            (
                "new-header-bytes-03".to_string(),
                b"value-bytes-03-a".to_vec(),
            ),
        ];

        let expected_bytes = expected_bytes.iter().collect::<HashSet<_>>();

        let diff = headers
            .difference(&original_headers)
            .collect::<HashSet<_>>();

        let diff_bytes = headers_bytes
            .difference(&original_headers_bytes)
            .collect::<HashSet<_>>();

        let diff = diff.difference(&expected).collect::<Vec<_>>();

        if !diff.is_empty() {
            println!("different headers: {:?}", diff);
            self.send_http_response(552, vec![], None);
            return Action::Pause;
        }

        let diff_bytes = diff_bytes.difference(&expected_bytes).collect::<Vec<_>>();
        if !diff_bytes.is_empty() {
            println!("different headers bytes: {:?}", diff_bytes);
            self.send_http_response(552, vec![], None);
            return Action::Pause;
        }

        // check if the response header is not returned
        if self.get_http_response_header("host").is_some() {
            self.send_http_response(553, vec![], None);
            return Action::Pause;
        };
        if self.get_http_response_header_bytes("host").is_some() {
            self.send_http_response(553, vec![], None);
            return Action::Pause;
        };

        let response_headers = self.get_http_response_headers();
        if response_headers.len() != 1 {
            self.send_http_response(555, vec![], None);
            return Action::Pause;
        }
        let Some((name, value)) = response_headers.into_iter().next() else {
            self.send_http_response(555, vec![], None);
            return Action::Pause;
        };
        if name != "new-response-header" || value != "value-02" {
            self.send_http_response(556, vec![], None);
            return Action::Pause;
        }

        Action::Continue
    }

    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        let mut original_headers = HashSet::new();
        let mut original_headers_bytes = HashSet::new();

        // iterate over the headers and print them
        for (name, value) in self.get_http_response_headers().into_iter() {
            println!("#{} -> {}: {}", self.context_id, name, value);
            original_headers.insert((name, value));
        }
        for (name, value) in self.get_http_response_headers_bytes().into_iter() {
            println!("#{} -> {}: {:?}", self.context_id, name, value);
            original_headers_bytes.insert((name, value));
        }
        if original_headers.is_empty() || original_headers_bytes.is_empty() {
            self.send_http_response(550, vec![], None);
            return Action::Pause;
        }

        // check if the host header is present
        if self.get_http_response_header("host").is_none() {
            self.send_http_response(551, vec![], None);
            return Action::Pause;
        }
        if self.get_http_response_header_bytes("host").is_none() {
            self.send_http_response(551, vec![], None);
            return Action::Pause;
        }

        // add new headers
        self.add_http_response_header("new-header-01", "value-01");
        self.add_http_response_header_bytes("new-header-bytes-01", b"value-bytes-01");

        self.add_http_response_header("new-header-02", "value-02");
        self.add_http_response_header_bytes("new-header-bytes-02", b"value-bytes-02");

        self.add_http_response_header("new-header-03", "value-03");
        self.add_http_response_header_bytes("new-header-bytes-03", b"value-bytes-03");

        //remove header new-headter-01, expected empty value
        self.set_http_response_header("new-header-01", None);
        self.set_http_response_header_bytes("new-header-bytes-01", None);

        // changing header value
        self.set_http_response_header("new-header-02", Some("new-value-02"));
        self.set_http_response_header_bytes("new-header-bytes-02", Some(b"new-value-bytes-02"));

        // add new header with existing name
        self.add_http_response_header("new-header-03", "value-03-a");
        self.add_http_response_header_bytes("new-header-bytes-03", b"value-bytes-03-a");

        // get new headers
        let headers = self
            .get_http_response_headers()
            .into_iter()
            .collect::<HashSet<(String, String)>>();
        let headers_bytes = self
            .get_http_response_headers_bytes()
            .into_iter()
            .collect::<HashSet<(String, Bytes)>>();

        let expected = [
            ("new-header-01".to_string(), "".to_string()),
            ("new-header-bytes-01".to_string(), "".to_string()),
            ("new-header-02".to_string(), "new-value-02".to_string()),
            (
                "new-header-bytes-02".to_string(),
                "new-value-bytes-02".to_string(),
            ),
            ("new-header-03".to_string(), "value-03".to_string()),
            (
                "new-header-bytes-03".to_string(),
                "value-bytes-03".to_string(),
            ),
            ("new-header-03".to_string(), "value-03-a".to_string()),
            (
                "new-header-bytes-03".to_string(),
                "value-bytes-03-a".to_string(),
            ),
        ];

        let expected = expected.iter().collect::<HashSet<_>>();

        let expected_bytes = [
            ("new-header-01".to_string(), b"".to_vec()),
            ("new-header-bytes-01".to_string(), b"".to_vec()),
            ("new-header-02".to_string(), b"new-value-02".to_vec()),
            (
                "new-header-bytes-02".to_string(),
                b"new-value-bytes-02".to_vec(),
            ),
            ("new-header-03".to_string(), b"value-03".to_vec()),
            (
                "new-header-bytes-03".to_string(),
                b"value-bytes-03".to_vec(),
            ),
            ("new-header-03".to_string(), b"value-03-a".to_vec()),
            (
                "new-header-bytes-03".to_string(),
                b"value-bytes-03-a".to_vec(),
            ),
        ];

        let expected_bytes = expected_bytes.iter().collect::<HashSet<_>>();

        let diff = headers
            .difference(&original_headers)
            .collect::<HashSet<_>>();

        let diff_bytes = headers_bytes
            .difference(&original_headers_bytes)
            .collect::<HashSet<_>>();

        let diff = diff.difference(&expected).collect::<Vec<_>>();

        if !diff.is_empty() {
            println!("different headers: {:?}", diff);
            self.send_http_response(552, vec![], None);
            return Action::Pause;
        }

        let diff_bytes = diff_bytes.difference(&expected_bytes).collect::<Vec<_>>();
        if !diff_bytes.is_empty() {
            println!("different headers bytes: {:?}", diff_bytes);
            self.send_http_response(552, vec![], None);
            return Action::Pause;
        }

        Action::Continue
    }
}
```

### FILE: examples/cdn/headers/Cargo.toml

```toml
[workspace]

[package]
name = "headers"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
```

### FILE: examples/cdn/headers/README.md

```
[← Back to examples](../../README.md)

# Headers (CDN)

Validates and manipulates HTTP request and response headers using the proxy-wasm ABI.
```
