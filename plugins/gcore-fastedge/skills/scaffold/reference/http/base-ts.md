<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: 81145a9a43ec499240c687bd49376ab20c72b11c
      updated: 2026-07-23
-->

---
type: base-skeleton
app_type: http
languages: [typescript, javascript]
template_origin: http-base
source_repo: https://github.com/G-Core/FastEdge-sdk-js
source_ref: 81145a9a43ec499240c687bd49376ab20c72b11c
updated: 2026-07-23
---

# Base Skeleton: HTTP TypeScript/JavaScript

## Directory Structure (TypeScript)

```
project-root/
├── .gitignore
├── package.json
├── tsconfig.json
└── src/
    └── index.ts
```

## Files

### src/index.ts

```typescript
async function eventHandler(event: FetchEvent): Promise<Response> {
  return new Response("Hello from FastEdge!");
}

addEventListener("fetch", (event: FetchEvent) => {
  event.respondWith(eventHandler(event));
});
```

### package.json

```json
{
  "name": "fastedge-basic-http-app",
  "description": "Basic HTTP example for FastEdge application",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc && npx fastedge-build --input ./src/index.ts --output ./wasm/basic-http.wasm --tsconfig ./tsconfig.json"
  },
  "devDependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.2.0",
    "typescript": "^5.0.0"
  }
}
```

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2023",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "lib": ["ES2023"],
    "types": ["@gcoredev/fastedge-sdk-js"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
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
npm run build
```

- **Build command (TypeScript)**: `tsc && npx fastedge-build --input ./src/index.ts --output ./wasm/basic-http.wasm --tsconfig ./tsconfig.json`
- **Output**: `./wasm/basic-http.wasm`
- **SDK**: `@gcoredev/fastedge-sdk-js` (provides types and `fastedge-build` CLI)

## JavaScript Variant

### Directory Structure (JavaScript)

```
project-root/
├── .gitignore
├── package.json
└── src/
    └── index.js
```

### src/index.js

```javascript
async function eventHandler(event) {
  const request = event.request;
  return new Response(`Hello, you made a request to ${request.url}`);
}

addEventListener("fetch", (event) => {
  event.respondWith(eventHandler(event));
});
```

### package.json (JavaScript)

```json
{
  "name": "fastedge-example-hello-world",
  "version": "1.0.0",
  "description": "FastEdge JS example: hello world request handler",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/hello-world.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0"
  }
}
```

- **Build command (JavaScript)**: `fastedge-build src/index.js dist/hello-world.wasm`
- No tsconfig.json needed
- No TypeScript dependency needed
