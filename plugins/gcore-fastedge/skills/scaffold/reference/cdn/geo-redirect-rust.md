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
capabilities: [geo-routing, geo-redirect]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/geo_redirect
---

# Geo Redirect — CDN (Rust)

Routes CDN requests to country-specific origins based on the client's geoIP country code. Falls back to a configurable default origin when no country-specific mapping is set.

## When to Use

Use this blueprint when you want to route requests to different origins based on the client's geographic location — for example, serving US traffic from a US origin and German traffic from a DE origin.

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `DEFAULT` | Yes | Fallback origin URL used when no country-specific mapping is found |
| `<COUNTRY_CODE>` | No | Per-country origin URL; variable name is the ISO country code (e.g. `US`, `DE`, `GB`) |

If `DEFAULT` is not set, the app returns HTTP 500 with body `App misconfigured - DEFAULT must be set`.

## Hook: `on_http_request_headers`

All routing logic executes in `on_http_request_headers`. No body hooks are used.

### Logic Flow

1. Read `DEFAULT` env var — return 500 if absent.
2. Read country code from `request.country` property — return 502 if empty or missing.
3. Look up `env::var(&country_code)`; fall back to `DEFAULT` if not set.
4. Strip trailing `/` from the resolved origin.
5. Read `request.path` property; default to `"/"` if absent.
6. Preserve the `Host` header by reading `request.host` and calling `set_http_request_header`.
7. Construct the target URL as `format!("{}{}", origin, path)`.
8. Log the target URL at `Info` level via `println!`.
9. Write the URL to `request.url` via `set_property` and return `Action::Continue`.

### Country Detection

```rust
let country_code = self
    .get_property(vec!["request.country"])
    .and_then(|bytes| String::from_utf8(bytes).ok())
    .unwrap_or_default();

if country_code.is_empty() {
    self.send_http_response(502, vec![], Some(b"Missing country information"));
    return Action::Pause;
}
```

`get_property` returns `Option<Vec<u8>>`. Decode with `.and_then(|b| String::from_utf8(b).ok()).unwrap_or_default()` for safe fallback to an empty string.

### Origin Resolution

```rust
let origin = env::var(&country_code).unwrap_or(default_origin);
let origin = origin.trim_end_matches('/');
```

The country code string (e.g. `"US"`) is used directly as the env var name. If no matching env var exists, `DEFAULT` is used.

### Path Preservation

```rust
let path = self
    .get_property(vec!["request.path"])
    .and_then(|bytes| String::from_utf8(bytes).ok())
    .unwrap_or_else(|| "/".to_string());
```

### Host Header Preservation

```rust
if let Some(host) = self
    .get_property(vec!["request.host"])
    .and_then(|bytes| String::from_utf8(bytes).ok())
{
    self.set_http_request_header("Host", Some(&host));
}
```

### URL Rewrite

```rust
let request_url = format!("{}{}", origin, path);
self.set_property(vec!["request.url"], Some(request_url.as_bytes()));
```

Sets `request.url` to redirect the CDN request to the resolved origin + path.

## Error Conditions

| Condition | Response |
|---|---|
| `DEFAULT` env var not set | HTTP 500, body: `App misconfigured - DEFAULT must be set`, `Action::Pause` |
| `request.country` empty or missing | HTTP 502, body: `Missing country information`, `Action::Pause` |

## Cargo.toml

```toml
[package]
name = "geo_redirect"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
```

Note: the workspace-level `[workspace]` key is present in the source Cargo.toml but omitted here as it is not relevant to the library package configuration.

## Struct Layout

| Struct | Traits | Role |
|---|---|---|
| `GeoRedirectRoot` | `Context`, `RootContext` | Entry point; creates HTTP contexts |
| `GeoRedirectContext` | `Context`, `HttpContext` | Handles request headers; performs routing |

`GeoRedirectRoot::get_type` returns `Some(ContextType::HttpContext)`.
`GeoRedirectRoot::create_http_context` returns `Some(Box::new(GeoRedirectContext))`.

## Entry Point

```rust
proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(GeoRedirectRoot) });
}}
```

## See Also

- cdn-base skeleton reference
- FastEdge-sdk-rust CDN examples overview
- proxy-wasm HttpContext trait reference
- host-services-rust reference (property access, header manipulation)
