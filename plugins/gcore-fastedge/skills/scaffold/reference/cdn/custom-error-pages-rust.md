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
capabilities: [error-pages, response-body]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/custom_error_pages
---

# Custom Error Pages — CDN App (Rust)

## When to Use

Use this pattern when you need to replace default 4xx/5xx error responses from the origin with custom branded HTML error pages at the CDN layer, before those error responses reach the client.

## Dependencies

```toml
[workspace]

[package]
name = "custom_error_pages"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
handlebars = "6.3"
serde_json = "1.0"
regex = "1.10"

[build-dependencies]
base64 = "0.22"
```

- `proxy-wasm` — Proxy-WASM ABI (CDN filter lifecycle hooks)
- `handlebars` — template rendering for HTML error pages
- `serde_json` — JSON data construction for Handlebars rendering context
- `regex` — available for pattern matching (declared as dependency)
- `base64` — build-time dependency for encoding images into the binary (not a runtime dependency)

## Build-Time Asset Embedding

This example uses a Rust build script (`build.rs`) to embed assets into the WASM binary at compile time. There is no filesystem access at runtime in WASM.

Two generated files are included at the top of `lib.rs`:

```rust
include!(concat!(env!("OUT_DIR"), "/image_map.rs"));
include!(concat!(env!("OUT_DIR"), "/message_map.rs"));
```

- `image_map.rs` — generated at build time; provides `get_image_map() -> HashMap<u16, &'static str>` returning Base64-encoded image strings keyed by status code. Special keys `4000` and `5000` are generic 4xx/5xx fallbacks.
- `message_map.rs` — generated at build time; provides `get_message_map() -> HashMap<u16, (&'static str, &'static str)>` returning `(title, description)` tuples keyed by status code. Same fallback keys apply.

Static files embedded at compile time via `include_str!`:

```rust
let error_template = include_str!("../templates/error_page.hbs");
let styles = include_str!("../public/styles.css");
```

- `templates/error_page.hbs` — Handlebars HTML template for error pages
- `public/styles.css` — CSS styles inlined into the rendered page

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

### `on_http_response_headers`

```rust
fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
    if let Some(status) = self.get_property(vec!["response.status"]) {
        if status.len() == 2 {
            let status_code = u16::from_be_bytes([status[0], status[1]]);
            if (400..600).contains(&status_code) {
                self.set_http_response_header("Content-Length", None);
                self.set_http_response_header("Transfer-Encoding", Some("Chunked"));
                self.set_http_response_header("Content-Type", Some("text/html"));
            }
        }
    }
    Action::Continue
}
```

**Status code detection:**

| Method | Signature | Description |
|---|---|---|
| `get_property` | `(path: Vec<&str>) -> Option<Vec<u8>>` | Reads a named property by path |

- Property path `["response.status"]` returns a 2-byte big-endian `u16` encoding the HTTP status code.
- Decode with: `u16::from_be_bytes([status[0], status[1]])`
- Guard with `status.len() == 2` before decoding.

**Header preparation for error responses (400–599):**

| Method | Signature | Description |
|---|---|---|
| `set_http_response_header` | `(name: &str, value: Option<&str>)` | Sets or removes a response header |

- `Content-Length` is removed (`None`) because the replacement body will have a different size.
- `Transfer-Encoding: Chunked` is set to allow streaming without a fixed content length.
- `Content-Type: text/html` is set because the replacement body is HTML.

### `on_http_response_body`

```rust
fn on_http_response_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
    let Some(status) = self.get_property(vec!["response.status"]) else {
        return Action::Continue;
    };
    if status.len() != 2 {
        return Action::Continue;
    }
    let status_code = u16::from_be_bytes([status[0], status[1]]);
    if !(400..600).contains(&status_code) {
        return Action::Continue;
    }

    if !end_of_stream {
        return Action::Pause;
    }

    // ... asset lookup, template rendering, body replacement
    Action::Continue
}
```

**Buffering pattern:** Return `Action::Pause` until `end_of_stream == true`. The host accumulates body chunks internally. Only process after the full body is available.

**Status code re-check:** `get_property(vec!["response.status"])` is called again in the body hook — property access is stateless and must be repeated per hook.

#### Status Code Fallback Logic

```rust
let base64_image = image_map
    .get(&status_code)
    .or_else(|| {
        if (400..500).contains(&status_code) {
            image_map.get(&4000)
        } else if (500..600).contains(&status_code) {
            image_map.get(&5000)
        } else {
            None
        }
    })
    .unwrap_or(&"");
```

Resolution order:
1. Exact match on `status_code` key in the map
2. If 4xx and no exact match: use key `4000` (generic 4xx fallback)
3. If 5xx and no exact match: use key `5000` (generic 5xx fallback)
4. If neither: empty string / default message

Same fallback logic applies to both `image_map` and `message_map`.

#### Default Message Fallback

```rust
.unwrap_or_else(|| {
    (
        "Unexpected Error".to_string(),
        "The server responded with a {{status}} error.".to_string(),
    )
})
```

If neither an exact match nor a generic fallback exists in `message_map`, the title defaults to `"Unexpected Error"` and description to `"The server responded with a {{status}} error."`.

#### Handlebars Template Rendering

```rust
let mut handlebars = Handlebars::new();

handlebars
    .register_template_string("message_template", message)
    .unwrap();
handlebars
    .register_template_string("description_template", description)
    .unwrap();

let msg_data = json!({
    "status": status_code.to_string(),
});

let complete_message = handlebars.render("message_template", &msg_data).unwrap();
let complete_description = handlebars
    .render("description_template", &msg_data)
    .unwrap();
```

- `message` and `description` strings may contain Handlebars `{{status}}` placeholders.
- `serde_json::json!` macro constructs the data context.
- Templates are registered by name and rendered with the same context.

```rust
let error_template = include_str!("../templates/error_page.hbs");
handlebars
    .register_template_string("error_template", error_template)
    .unwrap();

let styles = include_str!("../public/styles.css");
let page_data = json!({
    "styles": styles,
    "status": status_code.to_string(),
    "message": complete_message,
    "description": complete_description,
    "image": base64_image,
});

let html_body = handlebars.render("error_template", &page_data).unwrap();
```

Template data fields passed to `error_page.hbs`:

| Field | Type | Description |
|---|---|---|
| `styles` | `&str` | Full CSS content from `public/styles.css` |
| `status` | `String` | HTTP status code as string |
| `message` | `String` | Rendered title string |
| `description` | `String` | Rendered description string |
| `image` | `&str` | Base64-encoded image (or empty string) |

#### Body Replacement

```rust
let body = html_body.as_bytes();
self.set_http_response_body(0, body_size, body);
```

| Method | Signature | Description |
|---|---|---|
| `set_http_response_body` | `(start: usize, size: usize, value: &[u8])` | Replaces response body bytes |

- `start`: byte offset (use `0` for full replacement).
- `size`: number of bytes to replace (pass `body_size` from the hook parameter — the original body size).
- `value`: new body content as a byte slice.

## Adding a Custom Error Page

1. Add an image: `public/images/<status>.jpg`
2. Add a message file: `public/messages/<status>.hbs` (first line = title, second line = description)
3. Recompile and redeploy — the build script reads these files and generates updated maps.

## Styling

Edit `public/styles.css` directly. No build tools required. Styles are embedded at compile time via `include_str!`.

## Constraints

- No filesystem access at runtime — all assets (images, messages, templates, CSS) must be embedded at compile time.
- `include!` with `env!("OUT_DIR")` requires a `build.rs` build script to generate the map files.
- `handlebars.render(...).unwrap()` — panics if template rendering fails (invalid template syntax or missing data fields).
- `status.len() == 2` guard is required before decoding `response.status` bytes; the property may be absent or malformed.
- `Content-Length` must be removed before body replacement; leaving it set with an incorrect value causes protocol errors.
- Body replacement is only valid after `end_of_stream == true`.
- `get_property(vec!["response.status"])` must be called independently in each hook — property state is not shared across hook invocations.

## See Also

- cdn-base skeleton reference
- proxy-wasm HttpContext trait reference
- host-services-rust reference (property API)
- platform-overview reference (CDN app lifecycle)
- body-rust blueprint (general body manipulation pattern)

## Source Material

### FILE: examples/cdn/custom_error_pages/src/lib.rs

```rust
use handlebars::Handlebars;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use serde_json::json;
use std::collections::HashMap;
use std::env;

// Include the generated image map
include!(concat!(env!("OUT_DIR"), "/image_map.rs"));
include!(concat!(env!("OUT_DIR"), "/message_map.rs"));

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpBodyRoot) });
}}

struct HttpBodyRoot;

impl Context for HttpBodyRoot {}

impl RootContext for HttpBodyRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HttpBody))
    }
}

struct HttpBody;

impl Context for HttpBody {}

impl HttpContext for HttpBody {
    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        if let Some(status) = self.get_property(vec!["response.status"]) {
            if status.len() == 2 {
                let status_code = u16::from_be_bytes([status[0], status[1]]);
                if (400..600).contains(&status_code) {
                    // Remove the Content-Length header if it exists, we are going to change the response body
                    self.set_http_response_header("Content-Length", None);
                    self.set_http_response_header("Transfer-Encoding", Some("Chunked"));
                    self.set_http_response_header("Content-Type", Some("text/html"));
                }
            }
        }
        Action::Continue
    }

    fn on_http_response_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
        // only process 4xx/5xx error responses
        let Some(status) = self.get_property(vec!["response.status"]) else {
            return Action::Continue;
        };
        if status.len() != 2 {
            return Action::Continue;
        }
        let status_code = u16::from_be_bytes([status[0], status[1]]);
        if !(400..600).contains(&status_code) {
            return Action::Continue;
        }

        if !end_of_stream {
            // wait for complete body
            return Action::Pause;
        }

        // Get the image and message maps
        let image_map = get_image_map();
        let message_map = get_message_map();

        // Get the Base64-encoded image for the status code or its fallback
        let base64_image = image_map
            .get(&status_code)
            .or_else(|| {
                if (400..500).contains(&status_code) {
                    image_map.get(&4000)
                } else if (500..600).contains(&status_code) {
                    image_map.get(&5000)
                } else {
                    None
                }
            })
            .unwrap_or(&"");

        // Get the message and description for the status code or its fallback
        let (message, description) = message_map
            .get(&status_code)
            .or_else(|| {
                if (400..500).contains(&status_code) {
                    message_map.get(&4000)
                } else if (500..600).contains(&status_code) {
                    message_map.get(&5000)
                } else {
                    None
                }
            })
            .map(|(msg, desc)| (msg.to_string(), desc.to_string()))
            .unwrap_or_else(|| {
                (
                    "Unexpected Error".to_string(),
                    "The server responded with a {{status}} error.".to_string(),
                )
            });

        let mut handlebars = Handlebars::new();
        // Use handlebars to complete message and description text allowing for usage of {{ status }} variable
        handlebars
            .register_template_string("message_template", message)
            .unwrap();
        handlebars
            .register_template_string("description_template", description)
            .unwrap();

        let msg_data = json!({
            "status": status_code.to_string(),
        });

        let complete_message = handlebars.render("message_template", &msg_data).unwrap();
        let complete_description = handlebars
            .render("description_template", &msg_data)
            .unwrap();

        // Render the error page using Handlebars
        let error_template = include_str!("../templates/error_page.hbs");
        handlebars
            .register_template_string("error_template", error_template)
            .unwrap();

        let styles = include_str!("../public/styles.css");
        let page_data = json!({
            "styles": styles,
            "status": status_code.to_string(),
            "message": complete_message,
            "description": complete_description,
            "image": base64_image,
        });

        let html_body = handlebars.render("error_template", &page_data).unwrap();
        let body = html_body.as_bytes();
        self.set_http_response_body(0, body_size, body);

        Action::Continue
    }
}
```

### FILE: examples/cdn/custom_error_pages/Cargo.toml

```toml
[workspace]

[package]
name = "custom_error_pages"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
handlebars = "6.3"
serde_json = "1.0"
regex = "1.10"

[build-dependencies]
base64 = "0.22"
```

### FILE: examples/cdn/custom_error_pages/README.md

```
[← Back to examples](../../README.md)

# Custom Error Pages (CDN)

Intercepts 4xx and 5xx error responses and replaces them with branded HTML error pages using Handlebars templates.

## How it works

A [build script](./build.rs) runs at compile time to embed images and messages from the `public/` folder into the WASM binary (since there is no filesystem at runtime).

At runtime, when an error response is detected:
1. **on_response_headers** — sets `Content-Type` to `text/html` for error responses
2. **on_response_body** — looks up the status code in the embedded image/message maps, falls back to generic `4xx`/`5xx` templates, and renders the error page using Handlebars

## Adding a custom error page

1. Add an image: `public/images/<status>.jpg`
2. Add a message file: `public/messages/<status>.hbs` (first line = title, second line = description)
3. Recompile and deploy

## Styling

Styles are in [`public/styles.css`](./public/styles.css) — plain CSS, no build tools required. Edit directly.
```
