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
app_type: http
languages: [rust]
capabilities: [diagnostic-logging, outbound-http]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/diagnostic_logging
---

# Feature: Diagnostic Logging (WASI, Rust)

## When to Use

Use this feature when you want to attach a structured outcome label to each request so it can be filtered and searched in the FastEdge platform log viewer. `set_user_diag` writes a single per-request tag — distinct from stdout — intended for filterable outcome labels, not verbose traces.

## Dependencies

Add to `Cargo.toml` relative to the base skeleton:

```toml
[dependencies]
wstd = "0.6"
fastedge = "0.4"   # required — provides set_user_diag
anyhow = "1"
```

`fastedge = "0.4"` is the addition beyond the base skeleton.

## Crate Type

```toml
[lib]
crate-type = ["cdylib"]
```

## Required Configuration

| Variable     | Type   | Required | Description                    |
|--------------|--------|----------|--------------------------------|
| `ORIGIN_URL` | string | yes      | Origin URL to proxy requests to |

## API

### `fastedge::utils::set_user_diag`

```rust
use fastedge::utils::set_user_diag;

pub fn set_user_diag(tag: &str);
```

- Writes a single diagnostic tag string to the FastEdge platform per-request log viewer.
- Called synchronously — not `async`, not awaited.
- Call at most once per request path (last call wins if called multiple times).
- The tag is distinct from stdout/stderr output.
- No return value; no error return.

## Formatting Convention

Use `logfmt`-style `key=value` pairs for the tag string. This enables filtering and slicing in log search tooling.

```
outcome=<verb> [key=value ...]
```

Verb vocabulary used in this example:

| Verb                 | Meaning                                      |
|----------------------|----------------------------------------------|
| `config_error`       | Required environment variable missing/empty  |
| `origin_unreachable` | Outbound HTTP request to origin failed       |
| `proxied`            | Request successfully proxied to origin       |

## Call Sites

### 1. Missing configuration — before returning 500

```rust
set_user_diag("outcome=config_error reason=origin_missing");
return Ok(Response::builder()
    .status(500)
    .header("content-type", "text/plain; charset=utf-8")
    .body(Body::from("ORIGIN_URL is not configured"))?);
```

### 2. Outbound failure — before returning 502

```rust
set_user_diag(&format!(
    "outcome=origin_unreachable method={method} path={path} err={e}"
));
return Ok(Response::builder()
    .status(502)
    .header("content-type", "text/plain; charset=utf-8")
    .body(Body::from("origin unreachable"))?);
```

### 3. Successful proxy — before returning proxied response

```rust
let status = resp.status().as_u16();
set_user_diag(&format!(
    "outcome=proxied method={method} path={path} status={status}"
));
```

## Complete Handler Pattern

```rust
use std::env;

use fastedge::utils::set_user_diag;
use wstd::http::body::Body;
use wstd::http::{Client, Request, Response};

#[wstd::http_server]
async fn main(req: Request<Body>) -> anyhow::Result<Response<Body>> {
    let method = req.method().as_str().to_string();
    let path = req.uri().path().to_string();

    // 1. Validate required config
    let origin = match env::var("ORIGIN_URL") {
        Ok(u) if !u.trim().is_empty() => u,
        _ => {
            set_user_diag("outcome=config_error reason=origin_missing");
            return Ok(Response::builder()
                .status(500)
                .header("content-type", "text/plain; charset=utf-8")
                .body(Body::from("ORIGIN_URL is not configured"))?);
        }
    };

    // 2. Proxy outbound request
    let outbound = Request::get(&origin).body(Body::empty())?;
    let resp = match Client::new().send(outbound).await {
        Ok(r) => r,
        Err(e) => {
            set_user_diag(&format!(
                "outcome=origin_unreachable method={method} path={path} err={e}"
            ));
            return Ok(Response::builder()
                .status(502)
                .header("content-type", "text/plain; charset=utf-8")
                .body(Body::from("origin unreachable"))?);
        }
    };

    // 3. Tag successful proxy and return response
    let status = resp.status().as_u16();
    set_user_diag(&format!(
        "outcome=proxied method={method} path={path} status={status}"
    ));

    let (parts, mut body) = resp.into_parts();
    let bytes = body.contents().await?;
    let content_type = parts
        .headers
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("application/octet-stream")
        .to_string();

    Ok(Response::builder()
        .status(parts.status)
        .header("content-type", content_type)
        .body(Body::from(bytes))?)
}
```

## Constraints and Behavior

- `set_user_diag` must be called before `return` on every exit path where a tag is desired — there is no deferred or automatic tagging.
- The tag string is a plain `&str`; no length limit is documented in the source.
- Only the outbound `GET` method is used in this example — the inbound method is captured for logging only.
- Response body is buffered fully into memory via `body.contents().await?` before forwarding.
- `content-type` is forwarded from the origin response; falls back to `application/octet-stream` if absent or non-UTF-8.

## See Also

- outbound-http feature reference (for `wstd::http::Client` usage patterns)
- http-base skeleton (base handler structure, entry point macro)
- platform-overview (log viewer, per-request diagnostics context)
- fastedge SDK Rust reference (full `fastedge::utils` API surface)
