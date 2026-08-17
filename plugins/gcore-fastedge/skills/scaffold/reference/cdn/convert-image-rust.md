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
capabilities: [image-conversion, response-body-transformation, content-negotiation]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/convert_image
---

# Convert Image — CDN Feature (Rust)

## When to Use

Use this feature when you need to transcode images (e.g., to AVIF) at the CDN edge based on the request file extension and User-Agent header. It avoids re-encoding already-cached originals by using cache variation via a custom `Image-Format` request header.

---

## Dependencies

```toml
[dependencies]
proxy-wasm = "0.2"
image = "0.25"
```

`crate-type` must be `["cdylib"]`.

---

## Environment Variables (Configuration)

| Variable              | Required | Type                        | Constraints     | Default | Description                                                      |
|-----------------------|----------|-----------------------------|-----------------|---------|------------------------------------------------------------------|
| `FORMATS_TO_TRANSFORM`| Yes      | Comma-separated strings     | Non-empty       | —       | File extensions to convert (e.g., `jpg,jpeg,png`). Note: `jpg` and `jpeg` are distinct entries. |
| `IGNORED_UA_LIST`     | No       | Comma-separated strings     | —               | —       | User-Agent substrings; requests matching any entry are skipped.  |
| `AVIF_SPEED`          | No       | u8                          | 1–10 inclusive  | 5       | AVIF encoding speed. Values outside range fall back to default.  |
| `AVIF_QUALITY`        | No       | u8                          | 1–100 inclusive | 70      | AVIF encoding quality. Values outside range fall back to default.|

Parameter helper behavior: if a variable is absent, empty, non-numeric, or out of range, the default is used and a trace log is emitted.

---

## Context Structure

```rust
struct ConvertImageRoot;
impl Context for ConvertImageRoot {}
impl RootContext for ConvertImageRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(ConvertImageContext))
    }
}

struct ConvertImageContext;
impl Context for ConvertImageContext {}
impl HttpContext for ConvertImageContext { /* see hooks below */ }
```

---

## Three-Hook Pipeline

### Hook 1: `on_http_request_headers`

**Purpose:** Determine whether the request targets a convertible image and signal intent via the `Image-Format` request header.

**Signature:**
```rust
fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action
```

**Logic:**

1. Always add `Image-Format: original` — serves as the cache key for the unconverted response.
2. Read `request.extension` property:
   ```rust
   let raw_ext = self.get_property(vec!["request.extension"]);
   // raw_ext: Option<Vec<u8>>
   let Some(ext) = raw_ext else { return Action::Continue; };
   let Ok(ext) = from_utf8(&ext) else { return Action::Continue; };
   if ext.is_empty() { return Action::Continue; }
   ```
   Safe decoding chain: `Option<Vec<u8>>` → check `None` → decode UTF-8 → check empty.
3. Check `FORMATS_TO_TRANSFORM` env var — if the extension is not in the comma-separated list, pass through unchanged.
4. Read `User-Agent` request header — if absent or empty, pass through.
5. Check `IGNORED_UA_LIST` env var — if the UA contains any listed substring, pass through.
6. If all checks pass, overwrite `Image-Format` header to `image/avif`:
   ```rust
   self.set_http_request_header("Image-Format", Some("image/avif"));
   ```

**Return:** `Action::Continue` in all branches.

**Cross-hook signal:** The `Image-Format` request header value (`original` vs `image/avif`) is read by the response-headers hook.

---

### Hook 2: `on_http_response_headers`

**Purpose:** On 200 responses flagged for conversion, set response headers and propagate the target content-type to the body hook via a property.

**Signature:**
```rust
fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action
```

**Logic:**

1. Read response status via `rsp_status()` helper (see below). If status is not 200, pass through.
2. Read `Image-Format` request header (set in hook 1). If absent, pass through.
3. Always add `Vary: Image-Format` response header so CDN caches original and converted responses separately.
4. If `Image-Format == "original"`, pass through without conversion.
5. Otherwise (conversion requested):
   ```rust
   self.set_http_response_header("Content-Length", None);          // remove
   self.set_http_response_header("Transfer-Encoding", Some("Chunked"));
   self.set_http_response_header("Content-Type", Some(content_type.as_str()));
   self.set_property(vec!["response.content-type"], Some(content_type.as_bytes()));
   ```
   The `response.content-type` property signals the body hook to perform conversion.

**Return:** `Action::Continue` in all branches.

---

### Hook 3: `on_http_response_body`

**Purpose:** Buffer the complete response body, decode the image, re-encode as AVIF, and write the result back.

**Signature:**
```rust
fn on_http_response_body(&mut self, body_size: usize, end_of_stream: bool) -> Action
```

**Logic:**

1. **Body buffering:** Return `Action::Pause` when `!end_of_stream` to accumulate the full body before processing.
   ```rust
   if !end_of_stream {
       return Action::Pause;
   }
   ```
2. Read `response.content-type` property. If absent, pass through (hook 2 did not signal conversion).
3. Decode UTF-8. On failure, send HTTP 500 and return `Action::Pause`.
4. Guard: if `content_type != "image/avif"`, pass through (should not occur in normal flow).
5. Retrieve full body:
   ```rust
   let body_bytes = self.get_http_response_body(0, body_size);
   ```
6. Decode image from memory using the `image` crate:
   ```rust
   let img = match load_from_memory(buf) {
       Ok(i) => i,
       Err(e) => {
           println!("cannot load image to memory {}, not converting", e);
           return Action::Continue;
       }
   };
   ```
7. Encode as AVIF using `AvifEncoder`:
   ```rust
   img.write_with_encoder(
       codecs::avif::AvifEncoder::new_with_speed_quality(
           &mut c,
           u8_param("AVIF_SPEED", 1, 10, 5),
           u8_param("AVIF_QUALITY", 1, 100, 70),
       )
   );
   ```
8. On success, write transformed bytes back:
   ```rust
   self.set_http_response_body(0, body_size, &out);
   ```
   On failure, log the error and continue (original body is served).

**Return:** `Action::Continue` in all branches (except `Action::Pause` on incomplete body or internal error).

---

## Helper: `rsp_status`

Decodes the `response.status` property, which is returned as a 2-byte big-endian `u16`. Defined as an `impl ConvertImageContext` method.

```rust
fn rsp_status(&mut self) -> Option<u16> {
    if let Some(status) = self.get_property(vec!["response.status"]) {
        if status.len() != 2 {
            println!("HTTP status property is not 2 bytes");
            return None;
        }
        return Some(u16::from_be_bytes([status[0], status[1]]));
    }
    None
}
```

Length check is required — if `get_property` returns anything other than exactly 2 bytes, return `None`.

---

## Helper: `u8_param`

Reads an env var as a `u8` with min/max clamping and fallback to default.

```rust
fn u8_param(name: &str, min: u8, max: u8, default: u8) -> u8
```

Fallback conditions (all log at trace level and return `default`):
- Variable not set or empty
- Value is not a valid integer
- Value is below `min`
- Value is above `max`

---

## Helper: `str_param`

Reads an env var as a non-empty `String`.

```rust
fn str_param(name: &str) -> Result<String, VarError>
```

Returns `Err(VarError::NotPresent)` if the variable is absent or empty.

---

## Cross-Hook Signalling Summary

| Signal                  | Set by               | Read by                   | Mechanism                                      |
|-------------------------|----------------------|---------------------------|------------------------------------------------|
| `Image-Format: original`| request hook (always)| response-headers hook     | request header                                 |
| `Image-Format: image/avif` | request hook (on match) | response-headers hook | request header                              |
| `response.content-type` | response-headers hook| response-body hook        | `set_property` / `get_property`               |
| `Vary: Image-Format`    | response-headers hook| CDN cache                 | response header                                |

---

## Entry Point

```rust
proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(ConvertImageRoot) });
}}
```

---

## Error Conditions

| Condition                              | Behavior                                          |
|----------------------------------------|---------------------------------------------------|
| No file extension in request path      | Pass through without transformation               |
| Extension not in `FORMATS_TO_TRANSFORM`| Pass through without transformation               |
| `FORMATS_TO_TRANSFORM` not set         | Pass through without transformation               |
| No or empty `User-Agent` header        | Pass through without transformation               |
| UA matches `IGNORED_UA_LIST` entry     | Pass through without transformation               |
| Response status not 200               | Pass through without transformation               |
| Response status property not exactly 2 bytes | Treat as missing status, pass through       |
| No response body (`get_http_response_body` returns None) | Log and continue (original served) |
| Image decode failure (`load_from_memory`) | Log error, serve original body               |
| AVIF encode failure                   | Log error, serve original body                    |
| `response.content-type` invalid UTF-8 | Send HTTP 500, return `Action::Pause`             |

---

## See Also

- cdn-base skeleton reference
- scaffold reference for CDN app type
- FastEdge SDK Rust host services reference (proxy-wasm ABI, `get_property`, `set_property`)
- platform overview (CDN app lifecycle, cache variation with `Vary` headers)

## Source Material

### FILE: examples/cdn/convert_image/src/lib.rs

```rust
use image::*;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::{env, env::VarError, io::Cursor, str::from_utf8};

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(ConvertImageRoot) });
}}

struct ConvertImageRoot;

impl Context for ConvertImageRoot {}

impl RootContext for ConvertImageRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(ConvertImageContext))
    }
}

struct ConvertImageContext;

impl Context for ConvertImageContext {}

impl HttpContext for ConvertImageContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        // this header is used to select correct image version from cache
        self.add_http_request_header("Image-Format", "original");

        // get extension
        let path = self.get_property(vec!["request.path"]).map(|v| String::from_utf8(v).unwrap_or_default()).unwrap_or_default();
        println!("request.path={path:?}");
        let raw_ext = self.get_property(vec!["request.extension"]);
        println!("request.extension={raw_ext:?}");
        let Some(ext) = raw_ext else {
            println!("No extension in request path, not transforming");
            return Action::Continue;
        };
        let Ok(ext) = from_utf8(&ext) else {
            println!("Invalid UTF-8 in request extension, not transforming");
            return Action::Continue;
        };
        if ext.is_empty() {
            println!("No extension in request path, not transforming");
            return Action::Continue;
        }

        // FORMATS_TO_TRANSFORM contains list of file extensions to transfor
        // note that jpg and jpeg are different extensions
        let Ok(image_list) = str_param("FORMATS_TO_TRANSFORM") else {
            println!("FORMATS_TO_TRANSFORM param is not set, not transforming");
            return Action::Continue;
        };
        if !image_list.split(',').any(|entry| entry == ext) {
            println!(
                "extension {} is not in the list of formats to transform: {}, not transforming",
                ext, image_list
            );
            return Action::Continue;
        }

        // requests from User agents that match substrings in the IGNORED_UA_LIST param are not transformed
        let Some(ua) = self.get_http_request_header("User-Agent") else {
            println!("User-Agent header is not set, not transforming");
            return Action::Continue;
        };
        if ua.is_empty() {
            println!("User-Agent header is not set, not transforming");
            return Action::Continue;
        }
        if let Ok(ua_to_ignore) = str_param("IGNORED_UA_LIST") {
            if ua_to_ignore.split(",").any(|entry| ua.contains(entry)) {
                println!("User-Agent is in ignore list, not transforming");
                return Action::Continue;
            }
        }

        // indicator for on_response_headers and for cache key
        self.set_http_request_header("Image-Format", Some("image/avif"));

        Action::Continue
    }

    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        // only process 200 responses
        if let Some(status) = self.rsp_status() {
            if status != 200 {
                println!(
                    "Response status is {} instead of expected 200, not transforming",
                    status
                );
                return Action::Continue;
            }
        } else {
            println!("Response status is not set, not transforming");
            return Action::Continue;
        }

        // if "Image-Format" request header is not set, don't convert the image
        let Some(content_type) = self.get_http_request_header("Image-Format") else {
            return Action::Continue;
        };
        // instruct cache to vary by this header so "original" and "image/avif" are cached separately
        self.add_http_response_header("Vary", "Image-Format");

        if content_type == "original" {
            return Action::Continue;
        };

        // image to be transformed, set headers accordingly
        self.set_http_response_header("Content-Length", None);
        self.set_http_response_header("Transfer-Encoding", Some("Chunked"));
        self.set_http_response_header("Content-Type", Some(content_type.as_str()));

        // indicate to on_http_response_body that transformation is needed
        self.set_property(vec!["response.content-type"], Some(content_type.as_bytes()));

        Action::Continue
    }

    fn on_http_response_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
        if !end_of_stream {
            // wait till we get complete body
            return Action::Pause;
        }

        let Some(content_type) = self.get_property(vec!["response.content-type"]) else {
            return Action::Continue;
        };

        let Ok(content_type) = from_utf8(&content_type) else {
            // should never happen
            println!("Invalid UTF-8 in Content-Type");
            self.send_http_response(500, vec![], None);
            return Action::Pause;
        };

        if content_type != "image/avif" {
            // should never happen
            println!(
                "Content-Type {} is not supported, not transforming",
                content_type
            );
            return Action::Continue;
        }

        if let Some(body_bytes) = self.get_http_response_body(0, body_size) {
            let buf = body_bytes.as_bytes();
            let img = match load_from_memory(buf) {
                Ok(i) => i,
                Err(e) => {
                    println!("cannot load image to memory {}, not converting", e);
                    return Action::Continue;
                }
            };

            let mut out = Vec::new();
            let mut c = Cursor::new(&mut out);
            let res = img.write_with_encoder(codecs::avif::AvifEncoder::new_with_speed_quality(
                &mut c,
                u8_param("AVIF_SPEED", 1, 10, 5),
                u8_param("AVIF_QUALITY", 1, 100, 70),
            ));

            match res {
                Ok(_) => {
                    println!(
                        "{} bytes -> {} bytes {}",
                        body_size,
                        out.len(),
                        content_type
                    );
                    self.set_http_response_body(0, body_size, &out)
                }
                Err(e) => println!("cannot store transformed image {}", e),
            }
        } else {
            println!("No response body to transform");
        }

        Action::Continue
    }
}

impl ConvertImageContext {
    fn rsp_status(&mut self) -> Option<u16> {
        if let Some(status) = self.get_property(vec!["response.status"]) {
            if status.len() != 2 {
                println!("HTTP status property is not 2 bytes");
                return None;
            }
            return Some(u16::from_be_bytes([status[0], status[1]]));
        }
        None
    }
}

fn str_param(name: &str) -> Result<String, VarError> {
    let val = env::var(name)?;
    if val.is_empty() {
        return Err(VarError::NotPresent);
    }

    Ok(val)
}

fn u8_param(name: &str, min: u8, max: u8, default: u8) -> u8 {
    let Ok(val) = env::var(name) else {
        println!("Param {} is not set, using default value {}", name, default);
        return default;
    };
    if val.is_empty() {
        println!("Param {} is not set, using default value {}", name, default);
        return default;
    }

    let val = match val.parse() {
        Err(_) => {
            println!(
                "Param {} is not a valid number, using default value {}",
                name, default
            );
            return default;
        }
        Ok(v) => v,
    };
    if val < min {
        println!(
            "Param {} is below minimum {}, using default value {}",
            name, min, default
        );
        return default;
    }
    if val > max {
        println!(
            "Param {} is above maximum {}, using default value {}",
            name, max, default
        );
        return default;
    }

    val
}
```


### FILE: examples/cdn/convert_image/Cargo.toml

```toml
[workspace]

[package]
name = "convert_image"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
image = "0.25"
```


### FILE: examples/cdn/convert_image/README.md

```
[← Back to examples](../../README.md)

# Convert Image (CDN)

Converts images to AVIF format on the fly using the proxy-wasm ABI. Only transforms requests matching configured file extensions and skips specified user agents.

## Configuration

- Environment variable: `FORMATS_TO_TRANSFORM` — comma-separated list of file extensions to convert (e.g. `jpg,jpeg,png`)
- Environment variable: `IGNORED_UA_LIST` — (optional) comma-separated list of User-Agent substrings to skip
- Environment variable: `AVIF_SPEED` — (optional) AVIF encoding speed, 1-10 (default: 5)
- Environment variable: `AVIF_QUALITY` — (optional) AVIF encoding quality, 1-100 (default: 70)

## How it works

1. **on_request_headers** — checks file extension and User-Agent, sets `Image-Format` header for cache variation
2. **on_response_headers** — sets response headers for AVIF content type on 200 responses
3. **on_response_body** — decodes the original image and re-encodes it as AVIF
```
