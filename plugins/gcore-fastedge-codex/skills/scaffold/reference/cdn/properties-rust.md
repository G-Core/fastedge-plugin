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
capabilities: [properties, geo, request-metadata]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/properties
---

# Properties (CDN) — Rust

Read and rewrite request properties (URL, path, host, query, geo-IP metadata) in a CDN app using the proxy-wasm ABI.

## When to Use

Use this pattern when you need to:
- Read request metadata (URL, path, host, scheme, query string, file extension)
- Read geo-IP data (country, city, ASN, lat/long, region, continent, country name)
- Rewrite request URL, path, or host at the CDN layer before upstream processing
- Forward raw property values as response headers for debugging or downstream use

## Available Request Property Paths

All property keys are string slices passed to `get_property` / `set_property`.

| Constant | Property Path | Description |
|---|---|---|
| `REQUEST_URI` | `"request.url"` | Full request URI |
| `REQUEST_HOST` | `"request.host"` | Request host |
| `REQUEST_PATH` | `"request.path"` | Request path |
| `REQUEST_SCHEME` | `"request.scheme"` | Request scheme (http/https) |
| `REQUEST_EXTENSION` | `"request.extension"` | File extension of the path |
| `REQUEST_QUERY` | `"request.query"` | Raw query string |
| `REQUEST_X_REAL_IP` | `"request.x_real_ip"` | Client real IP address |
| `REQUEST_COUNTRY` | `"request.country"` | ISO country code |
| `REQUEST_CITY` | `"request.city"` | City name |
| `REQUEST_ASN` | `"request.asn"` | Autonomous System Number |
| `REQUEST_GEO_LAT` | `"request.geo.lat"` | Geographic latitude |
| `REQUEST_GEO_LONG` | `"request.geo.long"` | Geographic longitude |
| `REQUEST_REGION` | `"request.region"` | Region/state |
| `REQUEST_CONTINENT` | `"request.continent"` | Continent code |
| `REQUEST_COUNTRY_NAME` | `"request.country.name"` | Full country name (null-delimited bytes) |

## Property-to-Response-Header Mapping

The source example forwards each extracted property as a response header:

| Property key | Response header |
|---|---|
| `request.url` | `request-uri` |
| `request.host` | `request-host` |
| `request.path` | `request-path` |
| `request.scheme` | `request-scheme` |
| `request.extension` | `request-extension` |
| `request.query` | `request-query` |
| `request.x_real_ip` | `request-x-real-ip` |
| `request.country` | `request-country` |
| `request.city` | `request-city` |
| `request.asn` | `request-asn` |
| `request.geo.long` | `request-long` |
| `request.geo.lat` | `request-lat` |
| `request.country.name` | `request-country-names` |
| `request.region` | `request-country-region` |
| `request.continent` | `request-continent` |

## Cargo.toml

```toml
[package]
name = "properties"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
log = "0.4"
proxy-wasm = "0.2"
querystring = "1.1"
```

## Skeleton

```rust
use log::info;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(PropertiesRoot) });
}}

struct PropertiesRoot;
impl Context for PropertiesRoot {}

impl RootContext for PropertiesRoot {
    fn create_http_context(&self, context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(PropertiesContext { context_id }))
    }
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct PropertiesContext {
    context_id: u32,
}
impl Context for PropertiesContext {}

impl HttpContext for PropertiesContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        // Read and rewrite properties here
        Action::Continue
    }

    fn on_log(&mut self) {
        info!("#{} completed.", self.context_id);
    }
}
```

## Reading a Property

`get_property` returns `Option<Vec<u8>>`. A missing property returns `None`.

```rust
fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
    let Some(country) = self.get_property(vec!["request.country"]) else {
        self.send_http_response(558, vec![], None);
        return Action::Pause;
    };
    // Decode bytes to string
    let country_str = String::from_utf8_lossy(&country);
    println!("country = {}", country_str);

    Action::Continue
}
```

**Signature:** `fn get_property(&self, path: Vec<&str>) -> Option<Vec<u8>>`

- Returns `None` if the property is unavailable — handle with `let Some(...) else { ... }` or `.unwrap_or_default()`
- Bytes must be decoded with `String::from_utf8_lossy()` for string properties
- Call within `on_http_request_headers`
- `request.extension` uses `.unwrap_or_default()` (empty bytes if absent) — no error response, as paths commonly have no file extension
- `request.query` uses a `match` with `None => Bytes::new()` fallback — no error response, as a missing query string is valid

## Forwarding Property Bytes as a Response Header

Use `add_http_response_header_bytes` to attach raw property bytes directly as a response header without a UTF-8 decode round-trip.

```rust
let Some(uri) = self.get_property(vec!["request.url"]) else {
    self.send_http_response(551, vec![], None);
    return Action::Pause;
};
self.add_http_response_header_bytes("request-uri", &uri);
```

**Signature:** `fn add_http_response_header_bytes(&self, name: &str, value: &[u8])`

## Rewriting a Property

Use `set_property` to overwrite the value of a request property before it is processed upstream.

```rust
// Rewrite the request URL
self.set_property(vec!["request.url"], Some(b"https://example.com/new-path"));

// Rewrite from a query parameter value
let query_str = String::from_utf8_lossy(&query);
let params = querystring::querify(&query_str);

if let Some(url) = params.iter().find_map(|(k, v)| {
    if "url".eq_ignore_ascii_case(k) { Some(v) } else { None }
}) {
    self.set_property(vec!["request.url"], Some(url.as_bytes()));
}
```

**Signature:** `fn set_property(&self, path: Vec<&str>, value: Option<&[u8]>)`

- Pass `Some(bytes)` to set a value, `None` to clear it
- Writable properties: `request.url`, `request.host`, `request.path`
- Geo and metadata properties (country, city, ASN, etc.) are read-only

## Query-Param Override Pattern

After extracting properties, check for override query parameters and rewrite the corresponding upstream request property if present:

| Query param | Overwrites |
|---|---|
| `?url=<value>` | `request.url` |
| `?host=<value>` | `request.host` |
| `?path=<value>` | `request.path` |

```rust
let query_str = std::str::from_utf8(&query).unwrap();
let params = querystring::querify(query_str);

if let Some(url) = params.iter().find_map(|(k, v)| {
    if "url".eq_ignore_ascii_case(k) { Some(v) } else { None }
}) {
    self.set_property(vec![REQUEST_URI], Some(url.as_bytes()));
}

if let Some(host) = params.iter().find_map(|(k, v)| {
    if "host".eq_ignore_ascii_case(k) { Some(v) } else { None }
}) {
    self.set_property(vec![REQUEST_HOST], Some(host.as_bytes()));
}

if let Some(path) = params.iter().find_map(|(k, v)| {
    if "path".eq_ignore_ascii_case(k) { Some(v) } else { None }
}) {
    self.set_property(vec![REQUEST_PATH], Some(path.as_bytes()));
}
```

## Setting Custom Nginx Log Fields

```rust
self.set_property(
    vec!["nginx.log_field1"],
    Some(b"from_wasm nginx.log_field1"),
);
```

Custom log fields can be set via `set_property` using the `nginx.` prefix.

## Deserializing Country Names

`request.country.name` returns null-byte-delimited bytes when multiple names are present. Use the helper below to split them.

```rust
pub fn deserialize_country_names(bytes: &[u8]) -> Vec<Cow<'_, str>> {
    let mut result = Vec::new();
    if bytes.is_empty() {
        return result;
    }
    let mut p = 0;
    while p < bytes.len() {
        let s = p;
        while p < bytes.len() && bytes[p] != 0 {
            p += 1;
        }
        result.push(String::from_utf8_lossy(&bytes[s..p]));
        p += 1;
    }
    result
}
```

**Signature:** `fn deserialize_country_names(bytes: &[u8]) -> Vec<Cow<'_, str>>`

- Input: raw bytes from `get_property(vec!["request.country.name"])`
- Output: vector of string slices (borrowed from input bytes where valid UTF-8, owned otherwise)
- Empty input returns an empty vector

## Complete Example

```rust
use log::info;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(PropertiesRoot) });
}}

struct PropertiesRoot;

impl Context for PropertiesRoot {}

impl RootContext for PropertiesRoot {
    fn create_http_context(&self, context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(PropertiesContext { context_id }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct PropertiesContext {
    context_id: u32,
}

impl Context for PropertiesContext {}

pub const REQUEST_URI: &str = "request.url";
pub const REQUEST_HOST: &str = "request.host";
pub const REQUEST_PATH: &str = "request.path";
pub const REQUEST_SCHEME: &str = "request.scheme";
pub const REQUEST_EXTENSION: &str = "request.extension";
pub const REQUEST_QUERY: &str = "request.query";
pub const REQUEST_X_REAL_IP: &str = "request.x_real_ip";
pub const REQUEST_COUNTRY: &str = "request.country";
pub const REQUEST_CITY: &str = "request.city";
pub const REQUEST_ASN: &str = "request.asn";
pub const REQUEST_GEO_LAT: &str = "request.geo.lat";
pub const REQUEST_GEO_LONG: &str = "request.geo.long";
pub const REQUEST_REGION: &str = "request.region";
pub const REQUEST_CONTINENT: &str = "request.continent";
pub const REQUEST_COUNTRY_NAME: &str = "request.country.name";

impl HttpContext for PropertiesContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let Some(uri) = self.get_property(vec![REQUEST_URI]) else {
            self.send_http_response(551, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-uri", &uri);

        let Some(host) = self.get_property(vec![REQUEST_HOST]) else {
            self.send_http_response(552, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-host", &host);

        let Some(path) = self.get_property(vec![REQUEST_PATH]) else {
            self.send_http_response(553, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-path", &path);

        let Some(scheme) = self.get_property(vec![REQUEST_SCHEME]) else {
            self.send_http_response(554, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-scheme", &scheme);

        // extension: unwrap_or_default — empty bytes if no file extension present
        let extension = self
            .get_property(vec![REQUEST_EXTENSION])
            .unwrap_or_default();
        self.add_http_response_header_bytes("request-extension", &extension);

        // query: fallback to empty bytes if absent — missing query string is valid
        let query = match self.get_property(vec![REQUEST_QUERY]) {
            None => Bytes::new(),
            Some(query) => {
                self.add_http_response_header_bytes("request-query", &query);
                query
            }
        };

        let Some(client_ip) = self.get_property(vec![REQUEST_X_REAL_IP]) else {
            self.send_http_response(557, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-x-real-ip", &client_ip);

        let Some(country) = self.get_property(vec![REQUEST_COUNTRY]) else {
            self.send_http_response(558, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-country", &country);

        let Some(city) = self.get_property(vec![REQUEST_CITY]) else {
            self.send_http_response(559, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-city", &city);

        let Some(asn) = self.get_property(vec![REQUEST_ASN]) else {
            self.send_http_response(560, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-asn", &asn);

        let Some(geo_long) = self.get_property(vec![REQUEST_GEO_LONG]) else {
            self.send_http_response(561, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-long", &geo_long);

        let Some(geo_lat) = self.get_property(vec![REQUEST_GEO_LAT]) else {
            self.send_http_response(562, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-lat", &geo_lat);

        let Some(country_name) = self.get_property(vec![REQUEST_COUNTRY_NAME]) else {
            self.send_http_response(563, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-country-names", &country_name);

        let Some(region) = self.get_property(vec![REQUEST_REGION]) else {
            self.send_http_response(564, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-country-region", &region);

        let Some(continent) = self.get_property(vec![REQUEST_CONTINENT]) else {
            self.send_http_response(565, vec![], None);
            return Action::Pause;
        };
        self.add_http_response_header_bytes("request-continent", &continent);

        // Query-param overrides: rewrite upstream request properties if override params present
        let query_str = std::str::from_utf8(&query).unwrap();
        let params = querystring::querify(query_str);

        if let Some(url) = params.iter().find_map(|(k, v)| {
            if "url".eq_ignore_ascii_case(k) { Some(v) } else { None }
        }) {
            self.set_property(vec![REQUEST_URI], Some(url.as_bytes()));
        }

        if let Some(host) = params.iter().find_map(|(k, v)| {
            if "host".eq_ignore_ascii_case(k) { Some(v) } else { None }
        }) {
            self.set_property(vec![REQUEST_HOST], Some(host.as_bytes()));
        }

        if let Some(path) = params.iter().find_map(|(k, v)| {
            if "path".eq_ignore_ascii_case(k) { Some(v) } else { None }
        }) {
            self.set_property(vec![REQUEST_PATH], Some(path.as_bytes()));
        }

        self.set_property(
            vec!["nginx.log_field1"],
            Some(b"from_wasm nginx.log_field1"),
        );

        Action::Continue
    }

    fn on_log(&mut self) {
        info!("#{} completed.", self.context_id);
    }
}
```

## Error Handling

| Condition | Response code | Behavior |
|---|---|---|
| `request.url` unavailable | 551 | `send_http_response`, return `Action::Pause` |
| `request.host` unavailable | 552 | `send_http_response`, return `Action::Pause` |
| `request.path` unavailable | 553 | `send_http_response`, return `Action::Pause` |
| `request.scheme` unavailable | 554 | `send_http_response`, return `Action::Pause` |
| `request.extension` unavailable | — | `unwrap_or_default()` — empty bytes, no error |
| `request.query` unavailable | — | `Bytes::new()` fallback — empty bytes, no error |
| `request.x_real_ip` unavailable | 557 | `send_http_response`, return `Action::Pause` |
| `request.country` unavailable | 558 | `send_http_response`, return `Action::Pause` |
| `request.city` unavailable | 559 | `send_http_response`, return `Action::Pause` |
| `request.asn` unavailable | 560 | `send_http_response`, return `Action::Pause` |
| `request.geo.long` unavailable | 561 | `send_http_response`, return `Action::Pause` |
| `request.geo.lat` unavailable | 562 | `send_http_response`, return `Action::Pause` |
| `request.country.name` unavailable | 563 | `send_http_response`, return `Action::Pause` |
| `request.region` unavailable | 564 | `send_http_response`, return `Action::Pause` |
| `request.continent` unavailable | 565 | `send_http_response`, return `Action::Pause` |

## Constraints

- All property reads and writes must occur within `on_http_request_headers`
- `get_property` returns `Option<Vec<u8>>` — always handle the `None` case explicitly
- `request.extension` and `request.query` use fallback defaults rather than error responses — missing values are valid for these properties
- Geo properties (`request.country`, `request.city`, `request.asn`, etc.) are read-only; only `request.url`, `request.host`, and `request.path` are writable via `set_property`
- `request.country.name` may contain multiple null-byte-delimited values; use `deserialize_country_names` to split them
- Decoded strings borrow from the original `Vec<u8>` via `String::from_utf8_lossy` — do not drop the source bytes while the `Cow<str>` is live
- `fixtures/force-server-properties.json` is a visual-debugger configuration file (no `.test.json` extension), not a test fixture; it seeds server-side properties when running in the FastEdge visual debugger

## See Also

- cdn-base skeleton (base proxy-wasm CDN app structure)
- host-services-rust reference (available host ABI functions)
- sdk-reference-rust reference (full proxy-wasm Rust API)
- platform-overview reference (CDN vs HTTP app types)

## Source Material

### FILE: examples/cdn/properties/src/lib.rs

```rust
use log::info;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(PropertiesRoot) });
}}

struct PropertiesRoot;

impl Context for PropertiesRoot {}

impl RootContext for PropertiesRoot {
    fn create_http_context(&self, context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(PropertiesContext { context_id }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

struct PropertiesContext {
    context_id: u32,
}

impl Context for PropertiesContext {}

pub const REQUEST_URI: &str = "request.url";
pub const REQUEST_HOST: &str = "request.host";
pub const REQUEST_PATH: &str = "request.path";
pub const REQUEST_SCHEME: &str = "request.scheme";
pub const REQUEST_EXTENSION: &str = "request.extension";
pub const REQUEST_QUERY: &str = "request.query";
pub const REQUEST_X_REAL_IP: &str = "request.x_real_ip";
pub const REQUEST_COUNTRY: &str = "request.country";
pub const REQUEST_CITY: &str = "request.city";
pub const REQUEST_ASN: &str = "request.asn";
pub const REQUEST_GEO_LAT: &str = "request.geo.lat";
pub const REQUEST_GEO_LONG: &str = "request.geo.long";
pub const REQUEST_REGION: &str = "request.region";
pub const REQUEST_CONTINENT: &str = "request.continent";
pub const REQUEST_COUNTRY_NAME: &str = "request.country.name";

impl HttpContext for PropertiesContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let Some(uri) = self.get_property(vec![REQUEST_URI]) else {
            self.send_http_response(551, vec![], None);
            return Action::Pause;
        };
        println!(" uri = {} ", String::from_utf8_lossy(&uri));
        self.add_http_response_header_bytes("request-uri", &uri);

        let Some(host) = self.get_property(vec![REQUEST_HOST]) else {
            self.send_http_response(552, vec![], None);
            return Action::Pause;
        };
        println!(" host = {} ", String::from_utf8_lossy(&host));
        self.add_http_response_header_bytes("request-host", &host);

        let Some(path) = self.get_property(vec![REQUEST_PATH]) else {
            self.send_http_response(553, vec![], None);
            return Action::Pause;
        };
        println!(" path = {} ", String::from_utf8_lossy(&path));
        self.add_http_response_header_bytes("request-path", &path);

        let Some(scheme) = self.get_property(vec![REQUEST_SCHEME]) else {
            self.send_http_response(554, vec![], None);
            return Action::Pause;
        };
        println!(" scheme = {} ", String::from_utf8_lossy(&scheme));
        self.add_http_response_header_bytes("request-scheme", &scheme);

        let extension = self
            .get_property(vec![REQUEST_EXTENSION])
            .unwrap_or_default();
        println!(" extension = {} ", String::from_utf8_lossy(&extension));
        self.add_http_response_header_bytes("request-extension", &extension);

        let query = match self.get_property(vec![REQUEST_QUERY]) {
            None => Bytes::new(),
            Some(query) => {
                println!(" query = {} ", String::from_utf8_lossy(&query));
                self.add_http_response_header_bytes("request-query", &query);
                query
            }
        };

        let Some(client_ip) = self.get_property(vec![REQUEST_X_REAL_IP]) else {
            self.send_http_response(557, vec![], None);
            return Action::Pause;
        };
        println!(" client_ip = {} ", String::from_utf8_lossy(&client_ip));
        self.add_http_response_header_bytes("request-x-real-ip", &client_ip);

        let Some(country) = self.get_property(vec![REQUEST_COUNTRY]) else {
            self.send_http_response(558, vec![], None);
            return Action::Pause;
        };
        println!(" country = {} ", String::from_utf8_lossy(&country));
        self.add_http_response_header_bytes("request-country", &country);

        let Some(city) = self.get_property(vec![REQUEST_CITY]) else {
            self.send_http_response(559, vec![], None);
            return Action::Pause;
        };
        println!(" city = {} ", String::from_utf8_lossy(&city));
        self.add_http_response_header_bytes("request-city", &city);

        let Some(value) = self.get_property(vec![REQUEST_ASN]) else {
            self.send_http_response(560, vec![], None);
            return Action::Pause;
        };
        println!(" asn = {} ", String::from_utf8_lossy(&value));
        self.add_http_response_header_bytes("request-asn", &value);

        let Some(value) = self.get_property(vec![REQUEST_GEO_LONG]) else {
            self.send_http_response(561, vec![], None);
            return Action::Pause;
        };
        println!(" long = {} ", String::from_utf8_lossy(&value));
        self.add_http_response_header_bytes("request-long", &value);

        let Some(value) = self.get_property(vec![REQUEST_GEO_LAT]) else {
            self.send_http_response(562, vec![], None);
            return Action::Pause;
        };
        println!(" lat = {} ", String::from_utf8_lossy(&value));
        self.add_http_response_header_bytes("request-lat", &value);

        let Some(value) = self.get_property(vec![REQUEST_COUNTRY_NAME]) else {
            self.send_http_response(563, vec![], None);
            return Action::Pause;
        };
        println!(" country names = {} ", String::from_utf8_lossy(&value));
        self.add_http_response_header_bytes("request-country-names", &value);

        let Some(value) = self.get_property(vec![REQUEST_REGION]) else {
            self.send_http_response(564, vec![], None);
            return Action::Pause;
        };
        println!(" region = {} ", String::from_utf8_lossy(&value));
        self.add_http_response_header_bytes("request-country-region", &value);

        let Some(value) = self.get_property(vec![REQUEST_CONTINENT]) else {
            self.send_http_response(565, vec![], None);
            return Action::Pause;
        };
        println!(" continent = {} ", String::from_utf8_lossy(&value));
        self.add_http_response_header_bytes("request-continent", &value);

        let query = std::str::from_utf8(&query).unwrap();
        println!("query={}", query);
        let params = querystring::querify(query);

        if let Some(url) = params.iter().find_map(|(k, v)| {
            if "url".eq_ignore_ascii_case(k) {
                Some(v)
            } else {
                None
            }
        }) {
            println!("change url to: {}", url);
            self.set_property(vec![REQUEST_URI], Some(url.as_bytes()));
        };

        if let Some(host) = params.iter().find_map(|(k, v)| {
            if "host".eq_ignore_ascii_case(k) {
                Some(v)
            } else {
                None
            }
        }) {
            println!("change host to: {}", host);
            self.set_property(vec![REQUEST_HOST], Some(host.as_bytes()));
        };

        if let Some(path) = params.iter().find_map(|(k, v)| {
            if "path".eq_ignore_ascii_case(k) {
                Some(v)
            } else {
                None
            }
        }) {
            println!("change path to: {}", path);
            self.set_property(vec![REQUEST_PATH], Some(path.as_bytes()));
        };

        self.set_property(
            vec!["nginx.log_field1"],
            Some(b"from_wasm nginx.log_field1"),
        );

        Action::Continue
    }

    fn on_log(&mut self) {
        info!("#{} completed.", self.context_id);
    }
}
```

### FILE: examples/cdn/properties/Cargo.toml

```toml
[workspace]

[package]
name = "properties"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
log = "0.4"
proxy-wasm = "0.2"
querystring = "1.1"
```

### FILE: examples/cdn/properties/README.md

```
[← Back to examples](../../README.md)

# Properties (CDN)

Extracts and manipulates request properties — URL, path, host, and geo data — using the proxy-wasm ABI. Forwards each extracted value as a response header so downstream clients or logging pipelines can inspect them.

## What it does

On every request, reads the following properties and adds each as a response header:

| Property key | Response header |
|---|---|
| `request.url` | `request-uri` |
| `request.host` | `request-host` |
| `request.path` | `request-path` |
| `request.scheme` | `request-scheme` |
| `request.extension` | `request-extension` |
| `request.query` | `request-query` |
| `request.x_real_ip` | `request-x-real-ip` |
| `request.country` | `request-country` |
| `request.city` | `request-city` |
| `request.asn` | `request-asn` |
| `request.geo.long` | `request-long` |
| `request.geo.lat` | `request-lat` |
| `request.country.name` | `request-country-names` |
| `request.region` | `request-country-region` |
| `request.continent` | `request-continent` |

If any property is missing the handler sends a 55x error response and stops — each property has a unique status code to identify exactly which lookup failed. `request.extension` is the exception: because a URL path often has no file extension, a missing value defaults to an empty string instead of triggering an error.

## Query-param overrides

After extracting all properties, the handler checks for override query parameters and rewrites the corresponding upstream request property if present:

| Query param | Overwrites |
|---|---|
| `?url=<value>` | `request.url` |
| `?host=<value>` | `request.host` |
| `?path=<value>` | `request.path` |

## nginx log field

Sets `nginx.log_field1` to `"from_wasm nginx.log_field1"` on every request, demonstrating how to write custom values into the CDN access log.

## Build

```sh
cargo build --release
# Output: target/wasm32-wasip1/release/properties.wasm
```

## Notes

`fixtures/force-server-properties.json` is a visual-debugger configuration file (no `.test.json` extension), not a test fixture. It is used to seed server-side properties when running the app in the FastEdge visual debugger.
```
