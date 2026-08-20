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
app_type: http
languages: [rust]
capabilities: [static-assets, path-routing]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/static_assets
---

# Feature Blueprint: Static Assets (WASI, Rust)

## When to Use

Use this blueprint when the user wants to embed static files (HTML, CSS, SVG, images) directly into the WASM binary at compile time and serve them by URL path. The FastEdge WASM runtime has no filesystem at runtime — all assets must be embedded at build time using `include_str!` (text) or `include_bytes!` (binary).

## Key APIs

### Asset embedding

```rust
include_str!("../assets/filename.ext")
```
- Embeds a UTF-8 text file into the binary at compile time.
- Path is relative to the source file containing the macro.
- Returns `&'static str`.
- Build fails if the target file does not exist at compile time.

```rust
include_bytes!("../assets/filename.ext")
```
- Embeds any file (including binary) into the binary at compile time.
- Returns `&'static [u8]`.
- For response body use: `bytes::Bytes::from_static(include_bytes!("..."))`

### Path routing

```rust
req.uri().path()   // -> &str
```
- Returns the request URI path (e.g. `"/"`, `"/style.css"`).
- Used to dispatch to the correct embedded asset.

### Status codes

```rust
wstd::http::StatusCode::OK          // 200
wstd::http::StatusCode::NOT_FOUND   // 404
```

### Response construction

```rust
Response::builder()
    .status(StatusCode::OK)
    .header("content-type", asset.content_type)
    .body(Body::from(asset.body))?
```

## Asset Struct Pattern

Define a struct to pair a content type with an embedded body:

```rust
struct Asset {
    content_type: &'static str,
    body: &'static str,
}
```

Declare each asset as a named `static` constant:

```rust
static INDEX_HTML: Asset = Asset {
    content_type: "text/html; charset=utf-8",
    body: include_str!("../assets/index.html"),
};
static STYLE_CSS: Asset = Asset {
    content_type: "text/css; charset=utf-8",
    body: include_str!("../assets/style.css"),
};
static LOGO_SVG: Asset = Asset {
    content_type: "image/svg+xml",
    body: include_str!("../assets/logo.svg"),
};
```

## Lookup Function Pattern

```rust
fn lookup(path: &str) -> Option<&'static Asset> {
    match path {
        "/" | "/index.html" => Some(&INDEX_HTML),
        "/style.css"        => Some(&STYLE_CSS),
        "/logo.svg"         => Some(&LOGO_SVG),
        _                   => None,
    }
}
```

- Multiple path patterns can map to the same asset (e.g. `"/"` and `"/index.html"`).
- Returns `None` for unrecognized paths — caller handles 404.

## Entry Point Pattern

```rust
#[wstd::http_server]
async fn main(req: Request<Body>) -> anyhow::Result<Response<Body>> {
    let path = req.uri().path();
    match lookup(path) {
        Some(asset) => Ok(Response::builder()
            .status(StatusCode::OK)
            .header("content-type", asset.content_type)
            .body(Body::from(asset.body))?),
        None => Ok(Response::builder()
            .status(StatusCode::NOT_FOUND)
            .header("content-type", "text/plain; charset=utf-8")
            .body(Body::from(format!("Not found: {path}\n")))?),
    }
}
```

## Imports

```rust
use wstd::http::body::Body;
use wstd::http::{Request, Response, StatusCode};
```

## Cargo.toml

```toml
[workspace]

[package]
name = "static_assets_wasi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
anyhow = "1"
```

## Files to Create

```
src/
  lib.rs               # Main handler — asset struct, statics, lookup, entry point
assets/
  index.html           # Placeholder HTML page
  style.css            # Placeholder stylesheet
  logo.svg             # Placeholder SVG image
Cargo.toml
```

All files in `assets/` must exist at compile time; the build will fail if `include_str!` targets a missing file.

## Constraints

- `include_str!` requires the file to be valid UTF-8. Use `include_bytes!` for binary assets (PNG, WOFF, etc.).
- Asset paths in `include_str!` are relative to the `.rs` source file, not the crate root.
- All assets are compiled into the WASM binary — large assets increase binary size proportionally.
- No dynamic file loading is possible at runtime; adding an asset requires a rebuild.
- The WASM runtime has no filesystem; there is no alternative to compile-time embedding.

## See Also

- http-base reference (base skeleton this feature extends)
- sdk-reference-rust (wstd HTTP types: Request, Response, Body, StatusCode)
- platform-overview (WASM runtime constraints, no filesystem)
- best-practices (binary size considerations, asset embedding guidelines)
