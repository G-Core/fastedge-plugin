<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-06-16
-->

---
type: base-skeleton
app_type: http
languages: [rust]
template_origin: http-base
source_repo: fastedge-sdk-rust
source_ref: 6347a7c2fda0d03e66f1214db5eec041c16801b7
updated: 2026-06-16

---

# Base Skeleton: HTTP Rust

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

### Cargo.toml

```toml
[workspace]

[package]
name = "hello_world"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
anyhow = "1"
```

### src/lib.rs

```rust
use wstd::http::body::Body;
use wstd::http::{Request, Response};

#[wstd::http_server]
async fn main(request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let url = request.uri().to_string();

    Ok(Response::builder()
        .status(200)
        .header("content-type", "text/plain;charset=UTF-8")
        .body(Body::from(format!(
            "Hello, you made a wasi request to {url}"
        )))?)
}
```

### .cargo/config.toml

```toml
[build]
target = "wasm32-wasip2"
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

FastEdge captures **stdout only**. Use `println!` / `print!` for any log line that needs to appear in the platform log API, the visual debugger, or `/gcore-fastedge:live-test` assertions.

**Do not use:**
- `eprintln!` / `eprint!` — write to stderr, silently dropped by the runtime
- `writeln!(std::io::stderr(), …)` or any direct `std::io::stderr()` writer
- `env_logger` with its default configuration — defaults to stderr; must be retargeted via `Builder::target(Target::Stdout)`
- `tracing_subscriber::fmt().with_writer(std::io::stderr)` — the default `fmt()` writes to stdout and is safe; explicit stderr overrides are not

If a log line does not appear when running `fastedge-run http -w ./target/wasm32-wasip2/release/<crate>.wasm`, it is on stderr and will be invisible in production too.

Example pattern for HTTP Rust:
```rust
async fn main(request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let path = request.uri().path().to_string();
    println!("request received: {path}");     // visible in FastEdge logs
    // eprintln!("request received: {path}"); // DO NOT use — dropped
    Ok(Response::builder()
        .status(200)
        .header("content-type", "text/plain;charset=UTF-8")
        .body(Body::from(format!("You called: {path}")))?)
}
```

## Build Configuration

```bash
cargo build --release --target wasm32-wasip2
```

- **Build command**: `cargo build --release --target wasm32-wasip2`
- **Output**: `./target/wasm32-wasip2/release/hello_world.wasm`
- **Target**: `wasm32-wasip2` (configured in `.cargo/config.toml`)
- **SDK**: `wstd` crate v0.6 (provides `#[wstd::http_server]` macro, Body, Request/Response types)
- **Error handling**: `anyhow` crate v1
- **Handler signature**: `async fn main(request: Request<Body>) -> anyhow::Result<Response<Body>>`
- **Crate type**: `cdylib` (required for WASM output)
- **Workspace**: Single-project workspace pattern (`[workspace]` declared in Cargo.toml)
