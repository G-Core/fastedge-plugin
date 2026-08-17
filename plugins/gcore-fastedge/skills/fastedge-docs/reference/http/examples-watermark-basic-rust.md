<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-08-17
-->

# HTTP Example: Watermark (Basic, Rust)

**App type**: HTTP  
**Language**: Rust  
**Handler**: `#[fastedge::http]` (sync, `wasm32-wasip1`)  
**Cargo package**: `watermark`

---

## What This Example Does

Fetches an image from an S3-compatible bucket using AWS Signature V4 request signing, overlays an embedded watermark PNG using per-pixel alpha blending, and returns the composited image in the original format with the correct MIME type. If the S3 response body is not a valid image, it is forwarded to the caller unchanged.

---

## Handler Signature

```rust
#[fastedge::http]
fn main(req: Request<Body>) -> Result<Response<Body>, Error>
```

- **Runtime**: sync (`wasm32-wasip1`)
- **Entry point macro**: `#[fastedge::http]`

---

## Request Handling

### Method filter

| Method | Behaviour |
|---|---|
| `GET`, `HEAD` | Allowed — processing continues |
| Any other | `405 Method Not Allowed`, header `Allow: GET, HEAD`, body `This method is not allowed\n` |

### Path extraction

- Filename extracted from `req.uri().path()` via `trim_start_matches('/')`.
- Empty path → `400 Bad Request`, body `Malformed request - filename expected\n`.

---

## S3 Integration

### Signed URL construction (`sign_s3`)

```rust
fn sign_s3(fname: &str) -> anyhow::Result<(Url, String)>
```

- Reads S3 credentials from env vars (see Environment Variables).
- Constructs `host` as `{REGION}.{BASE_HOSTNAME}`.
- Constructs `upload_url` as `{SCHEME}://{host}`.
- Creates a `rusty_s3::Bucket` with `UrlStyle::Path`.
- Signs a `GET` action with a 1-hour expiry (`Duration::from_secs(60 * 60)`).
- Returns `(signed_url: Url, host: String)`.
- Any error (missing env var, parse failure) → caller returns `500 Internal Server Error`, body `App misconfigured\n`.

### S3 fetch

```rust
fastedge::send_request(req: Request<Body>) -> Result<Response<Body>, Error>
```

- Outbound `GET` to signed S3 URL, with `Host` header set to computed `host`.
- Non-`200` S3 response → forwarded as-is to the caller (status + body unchanged).
- `send_request` error → `500 Internal Server Error`, empty body.

---

## Image Processing

### Format detection

```rust
image::guess_format(buf: &[u8]) -> Result<ImageFormat, ImageError>
```

- Applied to the S3 response body bytes.
- If format detection fails → S3 body forwarded to caller unchanged (not a valid image).

### Image decode

```rust
image::load_from_memory(buf: &[u8]) -> Result<DynamicImage, ImageError>
```

- Applied to both the S3 response body and the embedded watermark bytes.
- S3 body decode failure → body forwarded to caller unchanged.
- Watermark decode failure → `500 Internal Server Error`, body `Invalid watermark format\n` (should never occur at runtime if `sample.png` is valid at compile time).

### Watermark embedding

```rust
fn watermark(
    img: &DynamicImage,
    wm: &DynamicImage,
    offset_x: u32,
    offset_y: u32,
    opacity: f32,
) -> DynamicImage
```

- Per-pixel alpha blending over the region `[offset_x, offset_x+wm_width) × [offset_y, offset_y+wm_height)`.
- Watermark dimensions are clamped to image bounds: if `offset_x + wm_width > img_width`, `wm_width` is reduced to `img_width - offset_x`; same for height.
- Opacity clamped internally to `[0.0, 1.0]` (values above `1.0` clamped to `1.0`, below `0.0` clamped to `0.0`).
- Alpha blend formula per channel:
  - `img_alpha = img_pixel[3] / 255.0`
  - `wm_alpha = wm_pixel[3] / 255.0 * opacity`
  - `out_channel = wm_channel * wm_alpha + (1.0 - wm_alpha) * img_channel * img_alpha`
  - Output alpha is always set to `255`.
- Reads pixels with `DynamicImage::get_pixel(x, y)` and writes with `DynamicImage::put_pixel(x, y, pixel)` on a cloned canvas.
- In this example, `offset_x` and `offset_y` are hardcoded to `0` — watermark is placed at top-left.

### Result encoding

```rust
result.write_to(&mut Cursor::new(&mut out), out_format)
```

- Encodes composited `DynamicImage` back into the format detected by `guess_format`.
- Response `Content-Type` set via `out_format.to_mime_type()`.

---

## Watermark File Embedding

```rust
let wm_buf = include_bytes!("sample.png");
```

- Path is relative to `src/lib.rs` → resolves to `src/sample.png`.
- File **must exist at compile time**; a missing file is a compile error, not a runtime error.
- No runtime filesystem access required.

---

## Environment Variables

| Variable | Required | Type | Description |
|---|---|---|---|
| `ACCESS_KEY` | Yes | string | S3 access key ID |
| `SECRET_KEY` | Yes | string | S3 secret access key |
| `REGION` | Yes | string | S3 region (e.g. `us-east-1`) |
| `BASE_HOSTNAME` | Yes | string | S3 endpoint hostname (e.g. `cloud.gcore.lu`) |
| `BUCKET` | Yes | string | S3 bucket name |
| `SCHEME` | No | string | URL scheme for S3 endpoint (default: `http`) |
| `OPACITY` | No | float | Watermark opacity in `[0.0, 1.0]` (default: `1.0`) |

### OPACITY validation

- If `OPACITY` env var is absent → default `1.0` is used.
- Parsed via `l.parse::<f32>()`.
- Parse failure → `500 Internal Server Error`, body `Invalid opacity value\n`.
- Value outside `[0.0, 1.0]` → `500 Internal Server Error`, body `Invalid opacity value\n`.

---

## Response Behaviour

| Condition | Status | Body / Notes |
|---|---|---|
| Non-GET/HEAD method | `405 Method Not Allowed` | `This method is not allowed\n`; `Allow: GET, HEAD` header |
| Empty URL path | `400 Bad Request` | `Malformed request - filename expected\n` |
| Missing or invalid env vars (S3 config) | `500 Internal Server Error` | `App misconfigured\n` |
| `send_request` failure | `500 Internal Server Error` | Empty body |
| Non-`200` S3 response | Forwarded as-is | S3 status + body passed through to caller |
| S3 body not a valid image (`guess_format` or `load_from_memory` fails) | `200 OK` (forwarded) | S3 body passed through unchanged |
| Invalid `OPACITY` value (non-numeric or out of range) | `500 Internal Server Error` | `Invalid opacity value\n` |
| Invalid watermark format (`load_from_memory` fails on embedded PNG) | `500 Internal Server Error` | `Invalid watermark format\n` |
| Success | `200 OK` | Composited image; `Content-Type` from `out_format.to_mime_type()` |

---

## Dependencies (`Cargo.toml`)

```toml
[lib]
crate-type = ["cdylib"]

[dependencies]
fastedge = "0.4"
url = "2.3"
image = "0.24"
rusty-s3 = "0.5"
anyhow = "1"
```

---

## Build

```sh
cargo build --release
# Output: target/wasm32-wasip1/release/watermark.wasm
```

---

## Key APIs Used

| API | Crate | Purpose |
|---|---|---|
| `include_bytes!("sample.png")` | std | Embed watermark PNG at compile time |
| `fastedge::send_request(req)` | `fastedge` | Outbound HTTP request to S3 |
| `image::guess_format(buf)` | `image` | Detect image format from bytes |
| `image::load_from_memory(buf)` | `image` | Decode image from bytes into `DynamicImage` |
| `DynamicImage::get_pixel(x, y)` | `image` | Read pixel for alpha blending |
| `DynamicImage::put_pixel(x, y, pixel)` | `image` | Write blended pixel to canvas |
| `DynamicImage::write_to(&mut w, fmt)` | `image` | Encode composited image to bytes |
| `ImageFormat::to_mime_type()` | `image` | Get MIME type string for `Content-Type` |
| `rusty_s3::Bucket::new(url, style, bucket, region)` | `rusty-s3` | Construct S3 bucket handle |
| `rusty_s3::Credentials::new(access, secret)` | `rusty-s3` | Construct S3 credentials |
| `bucket.get_object(Some(&creds), fname)` | `rusty-s3` | Build S3 GET action |
| `action.sign(Duration::from_secs(3600))` | `rusty-s3` | Generate signed URL (1-hour expiry) |
| `std::env::var(key)` | std | Read app env vars |

---

## Gotchas

- `include_bytes!("sample.png")` resolves relative to `src/lib.rs`. The file must exist at compile time — its absence is a **compile error**.
- `OPACITY` must be a float in `[0.0, 1.0]`. Values outside this range or non-numeric strings return `500`.
- Signed S3 URLs expire after **1 hour**. Each request generates a fresh signed URL.
- Non-`200` S3 responses are forwarded as-is to the caller, potentially exposing S3 error details. The source code includes a commented alternative that returns a generic `500` instead.
- The watermark pixel loop clamps `wm_width` and `wm_height` to stay within the source image bounds relative to `offset_x`/`offset_y`.
- `offset_x` and `offset_y` are hardcoded to `0` in `main`. To support configurable placement, modify the `watermark(...)` call arguments.
- This example uses the legacy `#[fastedge::http]` sync handler (`wasm32-wasip1`). For new HTTP apps, prefer `#[wstd::http_server]` (async, `wasm32-wasip2`).

---

## See Also

- fastedge-docs platform-overview — FastEdge app model, env var configuration, deployment
- fastedge-docs sdk-reference-rust — `fastedge::send_request`, `Request`, `Response`, `Body`, `#[fastedge::http]`
- fastedge-docs best-practices — outbound request patterns, error handling conventions
- examples-s3-fetch (if available) — simpler S3 fetch without image processing

## Source Material

### FILE: examples/http/basic/watermark/src/lib.rs

```rust
// this example reads file from S3 storage, which must be confgiured for the app like this:
//   "env": {
//    "ACCESS_KEY": "<access_key>",
//    "BASE_HOSTNAME": "<base_hostname>, e.g. cloud.gcore.lu",
//    "BUCKET": "<bucket>",
//    "REGION": "<region>",
//    "SECRET_KEY": "<secret_key>"
//  }
// then apply watermark from file "sample.png", which is embedded during compilation process
// and return resulting image as PNG.
// if file from S3 cannot be recognised as valid image, it is passed to caller as is

const DEFAULT_OPACITY: f32 = 1.0; // to use non-default opacity, specify OPACITY in 0-1.0 range in app env

use fastedge::{
    body::Body,
    http::{header, Error, Method, Request, Response, StatusCode},
};
use image::*;
use rusty_s3::{Bucket, Credentials, S3Action, UrlStyle};
use std::{env, io::Cursor, time::Duration};
use url::Url;

#[fastedge::http]
fn main(req: Request<Body>) -> Result<Response<Body>, Error> {
    // embed watermark file - file must be present during compilation
    let wm_buf = include_bytes!("sample.png");

    // Filter request methods
    match req.method() {
        // Allow only GET and HEAD requests.
        &Method::GET | &Method::HEAD => (),

        // Deny anything else.
        _ => {
            return Response::builder()
                .status(StatusCode::METHOD_NOT_ALLOWED)
                .header(header::ALLOW, "GET, HEAD")
                .body(Body::from("This method is not allowed\n"));
        }
    };

    // get filename from URL with has format <scheme>://<host>/<filename>
    let filename = req.uri().path().trim_start_matches('/');
    if filename.is_empty() {
        return Response::builder()
            .status(StatusCode::BAD_REQUEST)
            .body(Body::from("Malformed request - filename expected\n"));
    }

    // construct S3 signed URL
    let (signed_url, host) = match sign_s3(filename) {
        Err(_) => {
            return Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .body(Body::from("App misconfigured\n"))
        }
        Ok((u, h)) => (u, h),
    };

    /* Actual request to S3 */
    let s3_req = Request::builder()
        .method(Method::GET)
        .uri(signed_url.as_str())
        .header("Host", host)
        .body(Body::empty())
        .expect("error building the request");
    let rsp = match fastedge::send_request(s3_req) {
        Err(_) => {
            return Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .body(Body::empty())
        }
        Ok(r) => r,
    };

    // if response is not 200, just forward it to the caller
    let (parts, body) = rsp.into_parts();
    if parts.status != StatusCode::OK {
        return Ok(Response::from_parts(parts, body));
        // if you don't want to expose S3 error to the caller, just use
        // return Response::builder()
        //     .status(StatusCode::INTERNAL_SERVER_ERROR)
        //     .body(Body::empty())
    }

    // load response as image
    let buf = body.as_bytes();
    let out_format = match guess_format(buf) {
        Ok(f) => f,
        Err(_e) =>
        // response body is not a valid image, just return it to the caller without changes
        {
            return Ok(Response::from_parts(parts, body))
        }
    };
    let img = match load_from_memory(buf) {
        Ok(i) => i,
        Err(_e) =>
        // response body is not a valid image, just return it to the caller without changes
        {
            return Ok(Response::from_parts(parts, body))
        }
    };

    // load watermark as image
    let wm_img = match load_from_memory(wm_buf.as_slice()) {
        Ok(i) => i,
        Err(_e) =>
        // should never happen
        {
            return Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .body(Body::from("Invalid watermark format\n"))
        }
    };

    // get opacity from env
    let opacity = match env::var("OPACITY").ok() {
        None => DEFAULT_OPACITY,
        Some(l) => match l.parse::<f32>() {
            Err(_) => {
                return Response::builder() // opacity is not a number
                    .status(StatusCode::INTERNAL_SERVER_ERROR)
                    .body(Body::from("Invalid opacity value\n"));
            }
            Ok(v) if !(0.0..=1.0).contains(&v) =>
            // opacity is not in 0-1.0 range
            {
                return Response::builder()
                    .status(StatusCode::INTERNAL_SERVER_ERROR)
                    .body(Body::from("Invalid opacity value\n"))
            }
            Ok(v) => v,
        },
    };

    let result = watermark(
        &img, &wm_img, 0, // X offset for watermark placement
        0, // Y offset for watermark placement
        opacity,
    );

    // convert resulting image to original format
    let mut out = Vec::new();
    let mut c = Cursor::new(&mut out);
    let _ = result.write_to(&mut c, out_format);

    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, out_format.to_mime_type())
        .body(Body::from(out))
}

// Apply watermark using alpha blending
fn watermark(
    img: &DynamicImage,
    wm: &DynamicImage,
    offset_x: u32,
    offset_y: u32,
    opacity: f32,
) -> DynamicImage {
    let opacity = match opacity {
        o if o > 1.0 => 1.0,
        o if o < 0.0 => 0.0,
        _ => opacity,
    };

    let img_width = img.width();
    let img_height = img.height();

    let mut wm_width = wm.width();
    let mut wm_height = wm.height();

    if offset_x + wm_width > img_width {
        wm_width = img_width - offset_x;
    }

    if offset_y + wm_height > img_height {
        wm_height = img_height - offset_y;
    }

    let mut canvas = img.clone();

    for y in 0..wm_height {
        for x in 0..wm_width {
            let img_x = x + offset_x;
            let img_y = y + offset_y;

            let mut img_pixel = img.get_pixel(img_x, img_y);
            let wm_pixel = wm.get_pixel(x, y);

            let img_alpha = img_pixel.0[3] as f32 / 255.0;
            let img_red = img_pixel.0[0] as f32 * img_alpha;
            let img_green = img_pixel.0[1] as f32 * img_alpha;
            let img_blue = img_pixel.0[2] as f32 * img_alpha;

            let wm_alpha = wm_pixel.0[3] as f32 / 255.0 * opacity;
            let wm_red = wm_pixel.0[0] as f32 * wm_alpha;
            let wm_green = wm_pixel.0[1] as f32 * wm_alpha;
            let wm_blue = wm_pixel.0[2] as f32 * wm_alpha;

            img_pixel.0[0] = (wm_red + (1.0 - wm_alpha) * img_red) as u8;
            img_pixel.0[1] = (wm_green + (1.0 - wm_alpha) * img_green) as u8;
            img_pixel.0[2] = (wm_blue + (1.0 - wm_alpha) * img_blue) as u8;
            img_pixel.0[3] = 255;

            canvas.put_pixel(img_x, img_y, img_pixel);
        }
    }

    canvas
}

// Calculate S3 signature
fn sign_s3(fname: &str) -> anyhow::Result<(Url, String)> {
    /* read S3 access params from env */
    let access_key = env::var("ACCESS_KEY")?;
    let secret_key = env::var("SECRET_KEY")?;
    let region = env::var("REGION")?;
    let base_hostname = env::var("BASE_HOSTNAME")?;
    let bucket = env::var("BUCKET")?;
    let scheme = env::var("SCHEME").unwrap_or_else(|_| "http".to_string());

    /* set S3 request params */
    let host = region.clone() + "." + base_hostname.as_str();
    let upload_url = scheme + "://" + host.as_str();
    let parsed_url = upload_url.parse()?;
    let bucket = Bucket::new(parsed_url, UrlStyle::Path, bucket, region)?;

    let creds = Credentials::new(access_key, secret_key);
    let action = bucket.get_object(Some(&creds), fname);
    let signed_url = action.sign(Duration::from_secs(60 * 60));

    Ok((signed_url, host))
}
```


### FILE: examples/http/basic/watermark/Cargo.toml

```toml
[workspace]

[package]
name = "watermark"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
fastedge = "0.4"
url = "2.3"
image = "0.24"
rusty-s3 = "0.5"
anyhow = "1"
```


### FILE: examples/http/basic/watermark/README.md

```
[← Back to examples](../../../README.md)

# Watermark

Demonstrates outbound S3 fetch and image compositing on the edge. The app retrieves an image from an S3-compatible bucket using request signing (`rusty_s3`), overlays an embedded watermark PNG (`sample.png`) using per-pixel alpha blending, and returns the composited image in the original format.

The watermark file (`src/sample.png`) is embedded at compile time via `include_bytes!` — no runtime filesystem access is needed.

Uses the legacy `#[fastedge::http]` sync handler (`wasm32-wasip1`). For new HTTP apps, prefer `#[wstd::http_server]` (async, `wasm32-wasip2`).

## What it does

1. Rejects non-GET/HEAD requests with `405 Method Not Allowed`.
2. Extracts the image filename from the URL path (e.g. `GET /photo.jpg`).
3. Constructs a time-limited AWS Signature V4 signed URL for the file in the configured S3 bucket.
4. Fetches the image from S3 via `fastedge::send_request`.
5. If the S3 response body is a valid image format, overlays the embedded watermark at the top-left corner.
6. Returns the composited image with the original MIME type.
7. If the S3 body is not a valid image, it is forwarded to the caller unchanged.

## Configuration

All environment variables are set on the deployed FastEdge app.

| Variable | Required | Description |
|---|---|---|
| `ACCESS_KEY` | ✅ | S3 access key ID |
| `SECRET_KEY` | ✅ | S3 secret access key |
| `REGION` | ✅ | S3 region (e.g. `us-east-1`) |
| `BASE_HOSTNAME` | ✅ | S3 endpoint hostname (e.g. `cloud.gcore.lu`) |
| `BUCKET` | ✅ | S3 bucket name |
| `SCHEME` | optional | URL scheme for S3 endpoint (default: `http`) |
| `OPACITY` | optional | Watermark opacity as a float in `0.0`–`1.0` (default: `1.0`) |

## Build

```sh
cargo build --release
# WASM output: target/wasm32-wasip1/release/watermark.wasm
```

## Expected behavior

| Request | Response |
|---|---|
| `POST /image.png` (wrong method) | `405 Method Not Allowed`, body: `This method is not allowed\n` |
| `GET /` (no filename) | `400 Bad Request`, body: `Malformed request - filename expected\n` |
| `GET /image.png` (env vars missing) | `500 Internal Server Error`, body: `App misconfigured\n` |
| `GET /image.png` (configured, image in bucket) | `200 OK`, watermarked image in original format |

## APIs used

| API | Purpose |
|---|---|
| `fastedge::send_request(req)` | Outbound HTTP request to S3 |
| `rusty_s3::{Bucket, Credentials, S3Action}` | AWS Signature V4 URL signing |
| `image::{load_from_memory, DynamicImage}` | Image decode, compositing, encode |
| `include_bytes!("sample.png")` | Embed watermark at compile time |
| `std::env::var` | Read S3 credentials and `OPACITY` from app env |

## Live testing

This example requires a real S3-compatible bucket (Gcore Object Storage or AWS S3) with valid credentials. The deterministic error paths (wrong method, empty path, missing env vars) can be validated locally with the fixture validator. The watermark compositing path requires a live deployment with credentials configured as app env vars.
```
