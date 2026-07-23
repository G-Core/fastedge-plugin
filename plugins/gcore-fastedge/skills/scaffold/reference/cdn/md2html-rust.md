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
capabilities: [response-body-transformation, content-type-rewriting, markdown-rendering]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/md2html
---

# md2html (CDN, Rust)

Converts Markdown documents returned by an origin server to HTML at the CDN edge using the proxy-wasm ABI. Optionally rewrites the upstream request path with a configurable base prefix.

## When to Use

Use this blueprint when you want to serve Markdown files from an origin as rendered HTML without modifying the origin, with optional base-path rewriting to locate raw `.md` files.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `BASE` | No | URL prefix prepended to the upstream request path. Trailing `/` is trimmed automatically. If absent, the request path is forwarded unchanged. |

## Dependencies

```toml
proxy-wasm = "0.2"
pulldown-cmark = "0.11"
```

Crate type must be `cdylib`.

## Hook Pipeline

This example implements three hooks in sequence across the CDN request/response lifecycle.

### 1. `on_http_request_headers`

**Purpose:** Strip `Accept-Encoding` to prevent a gzip-compressed response body that cannot be processed downstream; optionally prepend `BASE` to the request path.

**Behavior:**

1. Removes `Accept-Encoding` header unconditionally:
   ```rust
   self.set_http_request_header("Accept-Encoding", None);
   ```
   On the FastEdge CDN platform, this sets the header to an empty string rather than removing it entirely.

2. Reads the `BASE` environment variable. If absent, logs a message and returns `Action::Continue` without modifying the path.

3. Reads the current request path from the `request.path` property:
   ```rust
   self.get_property(vec!["request.path"])
   ```

4. Constructs the new path by concatenating `BASE` (trailing `/` trimmed) with the original path:
   ```rust
   let new_url = format!("{}{}", base.trim_end_matches('/'), url);
   ```

5. Writes the new path back:
   ```rust
   self.set_property(vec!["request.path"], Some(new_url.as_bytes()));
   ```

6. Returns `Action::Continue`.

**Error handling:**
- If reading the path as UTF-8 fails, sends a `400 Bad Request` response and returns `Action::Pause`.
- If the `request.path` property is missing (should never occur), defaults to `"/"`.

### 2. `on_http_response_headers`

**Purpose:** Detect Markdown responses and configure the response for body transformation.

**Behavior:**

1. Reads the `Content-Type` response header.
2. If `Content-Type` starts with `text/plain` or `text/markdown`:
   - Clears `Content-Length` (set to `None`) to allow body size change.
   - Sets `Transfer-Encoding` to `Chunked`.
   - Rewrites `Content-Type` to `text/html`.
   - Sets a cross-hook signal property:
     ```rust
     self.set_property(vec!["response.markdown"], Some(b"true"));
     ```
3. Returns `Action::Continue` in all cases.

**Cross-hook signalling:** The `response.markdown` property is a processing flag checked in `on_http_response_body`. Its presence (regardless of value) indicates conversion should proceed.

### 3. `on_http_response_body`

**Purpose:** Buffer the full response body, convert Markdown to HTML, and write the result back.

**Behavior:**

1. Checks for the `response.markdown` property:
   ```rust
   if None == self.get_property(vec!["response.markdown"]) {
       return Action::Continue;
   }
   ```
   If absent, passes the body through unchanged.

2. Buffers the complete body by pausing until `end_of_stream`:
   ```rust
   if !end_of_stream {
       return Action::Pause;
   }
   ```

3. Retrieves the full body:
   ```rust
   self.get_http_response_body(0, body_size)
   ```

4. Converts bytes to a UTF-8 string. If conversion fails, passes through unchanged.

5. Parses Markdown and converts to HTML using `pulldown_cmark`:
   ```rust
   let parser = Parser::new_ext(
       md.as_str(),
       Options::ENABLE_TABLES | Options::ENABLE_FOOTNOTES,
   );
   let mut html = String::new();
   html.push_str("<!DOCTYPE html><html><body>");
   pulldown_cmark::html::push_html(&mut html, parser);
   html.push_str("</body></html>");
   ```
   Enabled extensions: `ENABLE_TABLES`, `ENABLE_FOOTNOTES`.

6. Writes the HTML back over the original body:
   ```rust
   self.set_http_response_body(0, body_size, body);
   ```

7. Returns `Action::Continue`.

## Struct Layout

```
HttpBodyRoot        — RootContext; creates HttpBody per request
HttpBody            — HttpContext; implements all three hooks
```

Both structs implement `Context` (no-op). `HttpBodyRoot::get_type()` returns `Some(ContextType::HttpContext)`.

## Entry Point

```rust
proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HttpBodyRoot) });
}}
```

## Constraints and Notes

- `Accept-Encoding` removal is mandatory. Without it, the origin may return a gzip-compressed body that `pulldown_cmark` cannot parse.
- Body buffering via `Action::Pause` means the full Markdown body is held in memory before conversion. Large documents increase memory pressure.
- The `Content-Length` header must be cleared before `on_http_response_body` writes a body of different size; failure to do so causes a content-length mismatch.
- `Transfer-Encoding: Chunked` is set in response headers to signal that the body length is not predetermined.
- Path rewriting only occurs when `BASE` is set. The hook always strips `Accept-Encoding` regardless.

## See Also

- cdn-base skeleton reference
- proxy-wasm CDN context API reference (HttpContext trait)
- FastEdge CDN platform overview
- scaffold blueprint CDN shared rules (_scaffold-blueprint-cdn)
