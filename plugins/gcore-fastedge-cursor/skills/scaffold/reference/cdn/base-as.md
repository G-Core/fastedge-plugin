<!--
  auto-updated: true
  sources:
    - id: proxy-wasm-sdk-as
      ref: master
      commit: 8e3bb621bc013a0aed7e52122066b417ad62a207
      updated: 2026-08-20
-->

---
type: base-skeleton
app_type: cdn
languages: [assemblyscript]
template_origin: cdn-base
source_example: proxy-wasm-sdk-as/examples/helloWorld
source_repo: proxy-wasm-sdk-as
source_ref: 8e3bb621bc013a0aed7e52122066b417ad62a207
updated: 2026-08-20
---

# Base Skeleton: CDN AssemblyScript

## Directory Structure

```
project-root/
├── .gitignore
├── package.json
├── tsconfig.json
├── asconfig.json
└── assembly/
    └── index.ts
```

## Files

### assembly/index.ts
```typescript
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy"; // this exports the required functions for the proxy to interact with us.
import {
  Context,
  FilterDataStatusValues,
  FilterHeadersStatusValues,
  log,
  LogLevelValues,
  registerRootContext,
  RootContext,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";

class HelloWorldRoot extends RootContext {
  createContext(context_id: u32): Context {
    return new HelloWorld(context_id, this);
  }
}

class HelloWorld extends Context {
  constructor(context_id: u32, root_context: HelloWorldRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(
    headers: u32,
    end_of_stream: bool
  ): FilterHeadersStatusValues {
    log(LogLevelValues.info, "onRequestHeaders >>");
    return FilterHeadersStatusValues.Continue;
  }

  onRequestBody(
    body_buffer_length: usize,
    end_of_stream: bool
  ): FilterDataStatusValues {
    log(LogLevelValues.info, "onRequestBody >>");
    return FilterDataStatusValues.Continue;
  }

  onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    log(LogLevelValues.info, "onResponseHeaders >>");
    return FilterHeadersStatusValues.Continue;
  }

  onResponseBody(
    body_buffer_length: usize,
    end_of_stream: bool
  ): FilterDataStatusValues {
    log(LogLevelValues.info, "onResponseBody >>");
    return FilterDataStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => {
  return new HelloWorldRoot(context_id);
}, "helloWorld");
```

### package.json
```json
{
  "name": "fastedge-as-example-hello-world",
  "version": "1.0.0",
  "description": "FastEdge AssemblyScript example: Hello World — minimal CDN app skeleton",
  "scripts": {
    "asbuild:debug": "asc assembly/index.ts --target debug",
    "asbuild:release": "asc assembly/index.ts --target release",
    "asbuild": "npm run asbuild:debug && npm run asbuild:release"
  },
  "dependencies": {
    "@gcoredev/proxy-wasm-sdk-as": "^1.2.3"
  },
  "devDependencies": {
    "@assemblyscript/wasi-shim": "^0.1.0",
    "assemblyscript": "^0.28.9"
  }
}
```

### tsconfig.json
```json
{
  "extends": "assemblyscript/std/assembly.json",
  "include": ["./**/*.ts"]
}
```

### asconfig.json
```json
{
  "extends": "./node_modules/@assemblyscript/wasi-shim/asconfig.json",
  "targets": {
    "debug": {
      "outFile": "build/helloWorld-debug.wasm",
      "textFile": "build/helloWorld-debug.wat",
      "sourceMap": true,
      "debug": true
    },
    "release": {
      "outFile": "build/helloWorld.wasm",
      "textFile": "build/helloWorld.wat",
      "sourceMap": true,
      "optimizeLevel": 3,
      "shrinkLevel": 0,
      "converge": false,
      "noAssert": false
    }
  },
  "options": {
    "bindings": "esm",
    "use": "abort=abort_proc_exit"
  }
}
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

## Build Configuration

```bash
npm install
npm run asbuild:release
```

- **Build command (release)**: `asc assembly/index.ts --target release`
- **Build command (debug)**: `asc assembly/index.ts --target debug`
- **Output (release)**: `./build/helloWorld.wasm`
- **Output (debug)**: `./build/helloWorld-debug.wasm`
- **SDK**: `@gcoredev/proxy-wasm-sdk-as` v1.2.3 (AssemblyScript proxy-wasm SDK)
- **Compiler**: `assemblyscript` v0.28.9 (compiles TypeScript-like syntax to WASM)
- **WASI shim**: `@assemblyscript/wasi-shim` v0.1.0 (required for WASI compatibility; `asconfig.json` must extend wasi-shim config)
- **Required option**: `"use": "abort=abort_proc_exit"` in `asconfig.json` options (mandatory for WASM runtime compatibility)
- **Architecture**: RootContext + Context pattern with 4 lifecycle hooks:
  - `onRequestHeaders(headers: u32, end_of_stream: bool): FilterHeadersStatusValues`
  - `onRequestBody(body_buffer_length: usize, end_of_stream: bool): FilterDataStatusValues`
  - `onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues`
  - `onResponseBody(body_buffer_length: usize, end_of_stream: bool): FilterDataStatusValues`
- **Source directory**: `assembly/` (not `src/` — AssemblyScript convention)
- **Entry point export**: `export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy"` must be the first line — exports functions required for proxy interaction

## Lifecycle Hook Return Values

All hooks return values from enums provided by the SDK:

- `FilterHeadersStatusValues.Continue` — pass headers through to next filter/upstream
- `FilterDataStatusValues.Continue` — pass body data through
- `FilterDataStatusValues.StopIterationAndBuffer` — buffer body until `end_of_stream` is true before processing

## Registration

```typescript
registerRootContext((context_id: u32) => {
  return new HelloWorldRoot(context_id);
}, "helloWorld");
```

- `registerRootContext` must be called exactly once at module level
- Second argument is the root context name string; must match the name configured in the FastEdge CDN app settings

## Constraints

- `RootContext` subclass must implement `createContext(context_id: u32): Context` returning a `Context` subclass instance
- `Context` subclass constructor must call `super(context_id, root_context)`
- All 4 lifecycle hook methods are optional overrides; base class provides no-op defaults
- Body hooks: `end_of_stream` is `false` for chunked data; return `StopIterationAndBuffer` until `end_of_stream` is `true` to guarantee complete body availability
- When modifying body content, update the corresponding `content-length` header in the preceding headers hook (`onRequestHeaders` for request body, `onResponseHeaders` for response body)

## See Also

- sdk-reference-js (HTTP app equivalent for JavaScript/TypeScript)
- host-services-rust (host API services — HTTP calls, KV store, environment variables)
- platform-overview (CDN filter pipeline, hook execution order)
- examples-headers-cdn-assemblyscript (header manipulation feature blueprint)
- examples-body-cdn-assemblyscript (body transformation feature blueprint)

## Source Material

### FILE: examples/helloWorld/assembly/index.ts

```ts
export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy"; // this exports the required functions for the proxy to interact with us.
import {
  Context,
  FilterDataStatusValues,
  FilterHeadersStatusValues,
  log,
  LogLevelValues,
  registerRootContext,
  RootContext,
} from "@gcoredev/proxy-wasm-sdk-as/assembly";

class HelloWorldRoot extends RootContext {
  createContext(context_id: u32): Context {
    return new HelloWorld(context_id, this);
  }
}

class HelloWorld extends Context {
  constructor(context_id: u32, root_context: HelloWorldRoot) {
    super(context_id, root_context);
  }

  onRequestHeaders(
    headers: u32,
    end_of_stream: bool,
  ): FilterHeadersStatusValues {
    log(LogLevelValues.info, "onRequestHeaders >> Hello World!");
    return FilterHeadersStatusValues.Continue;
  }

  onRequestBody(
    body_buffer_length: usize,
    end_of_stream: bool,
  ): FilterDataStatusValues {
    log(LogLevelValues.info, "onRequestBody >> Hello World!");
    return FilterDataStatusValues.Continue;
  }

  onResponseHeaders(a: u32, end_of_stream: bool): FilterHeadersStatusValues {
    log(LogLevelValues.info, "onResponseHeaders >> Hello World!");
    return FilterHeadersStatusValues.Continue;
  }

  onResponseBody(
    body_buffer_length: usize,
    end_of_stream: bool,
  ): FilterDataStatusValues {
    log(LogLevelValues.info, "onResponseBody >> Hello World!");
    return FilterDataStatusValues.Continue;
  }
}

registerRootContext((context_id: u32) => {
  return new HelloWorldRoot(context_id);
}, "helloWorld");
```


### FILE: examples/helloWorld/package.json

```json
{
  "name": "fastedge-as-example-hello-world",
  "version": "1.0.0",
  "description": "FastEdge AssemblyScript example: Hello World — minimal CDN app skeleton",
  "scripts": {
    "asbuild:debug": "asc assembly/index.ts --target debug",
    "asbuild:release": "asc assembly/index.ts --target release",
    "asbuild": "npm run asbuild:debug && npm run asbuild:release"
  },
  "dependencies": {
    "@gcoredev/proxy-wasm-sdk-as": "^1.2.3"
  },
  "devDependencies": {
    "@assemblyscript/wasi-shim": "^0.1.0",
    "assemblyscript": "^0.28.9"
  }
}
```


### FILE: examples/helloWorld/asconfig.json

```json
{
  "extends": "./node_modules/@assemblyscript/wasi-shim/asconfig.json",
  "targets": {
    "debug": {
      "outFile": "build/helloWorld-debug.wasm",
      "textFile": "build/helloWorld-debug.wat",
      "sourceMap": true,
      "debug": true
    },
    "release": {
      "outFile": "build/helloWorld.wasm",
      "textFile": "build/helloWorld.wat",
      "sourceMap": true,
      "optimizeLevel": 3,
      "shrinkLevel": 0,
      "converge": false,
      "noAssert": false
    }
  },
  "options": {
    "bindings": "esm",
    "use": "abort=abort_proc_exit"
  }
}
```
