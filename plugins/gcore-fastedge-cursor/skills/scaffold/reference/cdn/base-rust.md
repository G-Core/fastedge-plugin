<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-07-23
-->

---
type: base-skeleton
app_type: cdn
languages: [rust]
template_origin: cdn-base
source_repo: https://github.com/G-Core/FastEdge-sdk-rust
source_ref: 6347a7c2fda0d03e66f1214db5eec041c16801b7
updated: 2026-07-23
---

# Base Skeleton: CDN Rust

## Directory Structure

```
project-root/
├── .gitignore
├── Cargo.toml
├── .cargo/
│   └── config.toml
└── src/
    └── lib.rs
```

## Files

### src/lib.rs
```rust
use log::info;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HelloWorldRoot) });
}}

struct HelloWorldRoot;

impl Context for HelloWorldRoot {}

impl RootContext for HelloWorldRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HelloWorld))
    }
}

struct HelloWorld;

impl Context for HelloWorld {}

impl HttpContext for HelloWorld {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        info!("Hello from on_http_request_headers");
        Action::Continue
    }

    fn on_http_request_body(&mut self, _: usize, _: bool) -> Action {
        info!("Hello from on_http_request_body");
        Action::Continue
    }

    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        self.add_http_response_header("x-powered-by", "FastEdge");
        info!("Hello from on_http_response_headers");
        Action::Continue
    }

    fn on_http_response_body(&mut self, _: usize, _: bool) -> Action {
        info!("Hello from on_http_response_body");
        Action::Continue
    }
}
```

### Cargo.toml
```toml
[workspace]

[package]
name = "hello_world"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
log = "0.4"
proxy-wasm = "0.2"
```

### .cargo/config.toml
```toml
[build]
target = "wasm32-wasip1"
```

### .gitignore
```gitignore
# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
lerna-debug.log*

# Dependencies & build artifacts
**/node_modules/
**/out/
**/dist/
**/build/
**/*.wasm
**/target/

# Binaries for programs and plugins
/bin
*.exe
*.exe~
*.dll
*.so
*.dylib

# other
.DS_Store
/coverage
/typings
.npm
.eslintcache

# dotenv environment variable files
.env
.env.*
!.env.example

# IDEs and editors
/.idea
.project
.classpath
.c9/
*.launch
.settings/
*.sublime-workspace

# IDE - VSCode
.vscode/*
!.vscode/settings.json
!.vscode/tasks.json
!.vscode/launch.json
!.vscode/extensions.json
.history/*
```

## Logging Convention

FastEdge captures **stdout only**. CDN Rust apps have two stdout-safe options — pick one and stay consistent:

1. **`log` crate macros via proxy-wasm** (used in the base skeleton above): `log::info!`, `log::warn!`, `log::error!`, `log::debug!`, `log::trace!`. The `proxy_wasm::main!` macro wires these through the proxy-wasm host ABI (`log_message` import), which the FastEdge runtime routes to stdout. Already configured by the base skeleton via `proxy_wasm::set_log_level(LogLevel::Trace)`.
2. **Direct `println!` / `print!`** — writes straight to stdout. Works, but unconventional for CDN filters; prefer the `log` crate macros for consistency with proxy-wasm idioms.

**Do not use:**
- `eprintln!` / `eprint!` — write to stderr, silently dropped by the runtime
- `writeln!(std::io::stderr(), …)` or any direct `std::io::stderr()` writer
- `env_logger` with its default configuration — defaults to stderr; the `log` facade is already wired by proxy-wasm, so do not initialize a competing backend

If a log line does not appear when running the visual debugger against a fixture, it is on stderr and will be invisible in production too.

Example pattern for CDN Rust:
```rust
fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
    log::info!("incoming request");      // visible in FastEdge logs
    // eprintln!("incoming request");    // DO NOT use — dropped
    Action::Continue
}
```

## Build Configuration

```bash
cargo build --release --target wasm32-wasip1
```

- **Build command**: `cargo build --release --target wasm32-wasip1`
- **Output**: `./target/wasm32-wasip1/release/hello_world.wasm`
- **Target**: `wasm32-wasip1` (configured in `.cargo/config.toml`)
- **SDK**: `proxy-wasm` crate v0.2 (proxy-wasm ABI for CDN edge processing)
- **Logging**: `log` crate v0.4
- **Crate type**: `cdylib` (required for WASM output)
- **Architecture**: RootContext + HttpContext pattern with 4 lifecycle hooks:
  - `on_http_request_headers(num_headers: usize, end_of_stream: bool) -> Action`
  - `on_http_request_body(body_size: usize, end_of_stream: bool) -> Action`
  - `on_http_response_headers(num_headers: usize, end_of_stream: bool) -> Action`
  - `on_http_response_body(body_size: usize, end_of_stream: bool) -> Action`
- **Entry point**: `proxy_wasm::main!` macro — sets log level and registers RootContext factory
- **RootContext**: implements `get_type() -> Option<ContextType>` returning `ContextType::HttpContext` and `create_http_context(_: u32) -> Option<Box<dyn HttpContext>>`
- **HttpContext**: all 4 hooks return `Action::Continue` in the base skeleton; `on_http_response_headers` adds `x-powered-by: FastEdge` response header via `self.add_http_response_header`

## Source Material

### FILE: examples/cdn/hello_world/src/lib.rs

```rust
use log::info;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(HelloWorldRoot) });
}}

struct HelloWorldRoot;

impl Context for HelloWorldRoot {}

impl RootContext for HelloWorldRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(HelloWorld))
    }
}

struct HelloWorld;

impl Context for HelloWorld {}

impl HttpContext for HelloWorld {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        info!("Hello from on_http_request_headers");
        Action::Continue
    }

    fn on_http_request_body(&mut self, _: usize, _: bool) -> Action {
        info!("Hello from on_http_request_body");
        Action::Continue
    }

    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        self.add_http_response_header("x-powered-by", "FastEdge");
        info!("Hello from on_http_response_headers");
        Action::Continue
    }

    fn on_http_response_body(&mut self, _: usize, _: bool) -> Action {
        info!("Hello from on_http_response_body");
        Action::Continue
    }
}
```

### FILE: examples/cdn/hello_world/Cargo.toml

```toml
[workspace]

[package]
name = "hello_world"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
log = "0.4"
proxy-wasm = "0.2"
```
