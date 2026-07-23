<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: b78b2a80317bb632af88010816d3e54afd3bd72d
      updated: 2026-06-16
-->

## How It Works

FastEdge runs inside a WebAssembly sandbox with no access to the host file system. Static files must be embedded directly into the `.wasm` binary at compile time.

The build pipeline uses [Wizer](https://github.com/bytecodealliance/wizer) for pre-initialization. Wizer executes all top-level JavaScript in the entry point before taking a memory snapshot. When `createStaticServer` is called at the top level, it iterates over the asset manifest and loads every file's bytes into WebAssembly linear memory. Wizer snapshots that memory state and writes it into the final binary. At runtime, assets are served directly from memory with no startup delay and no file system access.

This means:

- `createStaticServer` **must** be called at module top level, not inside a function or event handler.
- The asset manifest must be available before `fastedge-build` runs.
- Any file not included in the manifest at build time cannot be served at runtime.

## Quick Start Workflow

### Step 1: Scaffold (optional)

Use `fastedge-init` to scaffold a static site project with the correct directory structure and entry point:

```sh
npx fastedge-init
```

### Step 2: Write the entry point

```ts
/// <reference types="@gcoredev/fastedge-sdk-js" />
import { createStaticServer } from '@gcoredev/fastedge-sdk-js';
import { staticAssetManifest } from './asset-manifest.js';

// Must be at top level — Wizer snapshots this call
const server = createStaticServer(staticAssetManifest, {
  autoIndex:    ['index.html'],
  autoExt:      ['.html'],
  notFoundPage: '/404.html',
});

addEventListener('fetch', (event: FetchEvent) => {
  event.respondWith(
    server.serveRequest(event.request).then(
      (response) => response ?? new Response('Not found', { status: 404 }),
    ),
  );
});
```

### Step 3: Build

Using a config file (manifest generation is automatic when `type: 'static'`):

```sh
npx fastedge-build --config .fastedge/build-config.js
```

Or directly specifying input/output:

```sh
npx fastedge-build --input ./src/index.ts --output ./dist/app.wasm
```

## Build Config Fields

When using `fastedge-build` with `type: 'static'`, the asset manifest is generated automatically as part of the build pipeline — no manual `fastedge-assets` invocation is required. Set the following static-specific fields in `build-config.js`:

```js
// .fastedge/build-config.js
const config = {
  type:              'static',
  entryPoint:        '.fastedge/static-index.js',
  wasmOutput:        './dist/app.wasm',
  publicDir:         './public',
  assetManifestPath: './src/asset-manifest.ts',
  ignoreDotFiles:    true,
  ignoreWellKnown:   false,
  ignorePaths:       ['./public/drafts'],
};

export { config };
```

| Field               | Type                           | Required | Description                                                                                                                  |
| ------------------- | ------------------------------ | -------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `publicDir`         | `string`                       | Yes      | Directory to scan for static files to embed                                                                                  |
| `assetManifestPath` | `string`                       | No       | Output path for the generated asset manifest module (defaults to `.fastedge/build/static-asset-manifest.js`)                 |
| `contentTypes`      | `Array<ContentTypeDefinition>` | No       | Custom content-type rules prepended before built-in defaults                                                                 |
| `ignoreDotFiles`    | `boolean`                      | No       | When `true`, excludes files and directories whose names begin with `.`                                                       |
| `ignorePaths`       | `string[]`                     | No       | Additional paths to exclude from the manifest                                                                                |
| `ignoreWellKnown`   | `boolean`                      | No       | When `true`, excludes the `.well-known/` directory                                                                           |

All other `BuildConfig` fields are documented in the BUILD_CLI reference.

## Server Config

All `ServerConfig` fields are optional. Pass only the fields you need.

```typescript
interface ServerConfig {
  publicDirPrefix: string;
  routePrefix:     string;
  extendedCache:   Array<string | RegExp>;
  compression:     string[];
  notFoundPage:    string | null;
  autoExt:         string[];
  autoIndex:       string[];
  spaEntrypoint:   string | null;
}
```

| Field             | Type                      | Default | Description                                                                                               |
| ----------------- | ------------------------- | ------- | --------------------------------------------------------------------------------------------------------- |
| `publicDirPrefix` | `string`                  | `''`    | Prefix stripped from asset keys before matching request paths                                             |
| `routePrefix`     | `string`                  | `'/'`   | URL prefix stripped from incoming request paths before looking up asset keys                              |
| `extendedCache`   | `Array<string \| RegExp>` | `[]`    | Paths or patterns that receive a `Cache-Control: max-age=31536000` response header                        |
| `compression`     | `string[]`                | `[]`    | Content encodings to serve (e.g. `['br', 'gzip']`); matched against the request `Accept-Encoding` header |
| `notFoundPage`    | `string \| null`          | `null`  | Asset path to serve when no match is found (e.g. `'/404.html'`); only served for HTML-accepting requests  |
| `autoExt`         | `string[]`                | `[]`    | Extensions to append when no exact path match is found (e.g. `['.html']`)                                 |
| `autoIndex`       | `string[]`                | `[]`    | Index file names to try for directory requests (e.g. `['index.html']`)                                    |
| `spaEntrypoint`   | `string \| null`          | `null`  | Asset path served as the SPA fallback for unmatched routes; only served for HTML-accepting requests        |

### routePrefix

Use when mounting a static server under a URL subpath. The prefix is stripped from the request path before asset lookup.

```ts
// Assets have keys like '/logo.png', '/style.css'
// Requests arrive as '/static/logo.png', '/static/style.css'
const server = createStaticServer(manifest, { routePrefix: '/static' });
```

### extendedCache

Entries are path strings or regex-style strings prefixed with `regex:`. Regex strings use the format `regex:/pattern/flags` and are converted to `RegExp` objects during normalization.

```ts
const server = createStaticServer(manifest, {
  extendedCache: [
    '/assets/logo.png',
    'regex:/\\.woff2$/i',
  ],
});
```

### autoExt and autoIndex

`autoExt` appends extensions to the path when no exact match is found. `autoIndex` appends index file names when the request path ends with `/`.

```ts
// Request: /about   → tries /about.html
// Request: /docs/   → tries /docs/index.html
const server = createStaticServer(manifest, {
  autoExt:   ['.html'],
  autoIndex: ['index.html'],
});
```

### notFoundPage and spaEntrypoint

Both are only served for requests that include `text/html` or `*/*` in their `Accept` header. Non-HTML requests that match no asset receive a void response regardless of these settings.

`spaEntrypoint` is checked first. If it resolves to an asset, it is returned with `Cache-Control: no-store`. If not, `notFoundPage` is checked and returned with `status: 404` and `Cache-Control: no-store`.

```ts
// Client-side routing: all unmatched HTML requests get /index.html
const server = createStaticServer(manifest, {
  spaEntrypoint: '/index.html',
});

// Static site with explicit 404 page
const server = createStaticServer(manifest, {
  notFoundPage: '/404.html',
});
```

## createStaticServer API

```typescript
function createStaticServer(
  staticAssetManifest: StaticAssetManifest,
  serverConfig: Partial<ServerConfig>,
): StaticServer
```

Creates a static server that serves assets from an in-memory cache built from `staticAssetManifest`.

**Import:**

```ts
import { createStaticServer } from '@gcoredev/fastedge-sdk-js';
```

**Parameters:**

| Parameter             | Type                    | Description                                                                                        |
| --------------------- | ----------------------- | -------------------------------------------------------------------------------------------------- |
| `staticAssetManifest` | `StaticAssetManifest`   | Manifest generated automatically by `type: 'static'` build, or manually via `fastedge-assets` CLI |
| `serverConfig`        | `Partial<ServerConfig>` | Server behavior options; all fields are optional                                                   |

**Returns:** `StaticServer`

### StaticServer Methods

```typescript
interface StaticServer {
  serveRequest(request: Request): Promise<void | Response>;
  readFileString(path: string):   Promise<string>;
}
```

#### serveRequest

```typescript
serveRequest(request: Request): Promise<void | Response>
```

Looks up the asset matching `request.url`'s pathname and returns a `Response` with appropriate headers (`Content-Type`, `ETag`, `Last-Modified`, `Cache-Control`). Handles conditional requests (`If-None-Match`, `If-Modified-Since`) and content encoding negotiation based on `Accept-Encoding`.

- Only processes `GET` and `HEAD` requests. All other methods resolve to `void` immediately.
- Returns `void` (resolves to `undefined`) when no matching asset is found and no applicable `notFoundPage` or `spaEntrypoint` is configured. The caller must provide a fallback response.

```ts
addEventListener('fetch', (event: FetchEvent) => {
  event.respondWith(
    server.serveRequest(event.request).then(
      (response) => response ?? new Response('Not found', { status: 404 }),
    ),
  );
});
```

#### readFileString

```typescript
readFileString(path: string): Promise<string>
```

Returns the text content of the embedded asset at `path`. The asset must have been classified as a text type (`isText: true`) in the manifest at build time. Throws an error if no asset is found at the given path. Use this to read embedded HTML templates or other text files for further processing at runtime.

```ts
const html = await server.readFileString('/template.html');
```

## Critical Constraint: Top-Level Initialization

`createStaticServer()` **must** be called at the module top level, not inside a function, event handler, or `async` context. Wizer pre-initializes the binary by running all top-level module code before snapshotting memory. Calling `createStaticServer` inside a handler means Wizer never executes it — assets are not embedded, and the binary silently fails at runtime.

**Correct:**

```ts
import { createStaticServer } from '@gcoredev/fastedge-sdk-js';
import { staticAssetManifest } from './asset-manifest.js';

// Top-level: runs during Wizer pre-initialization
const server = createStaticServer(staticAssetManifest, {});

addEventListener('fetch', (event: FetchEvent) => {
  event.respondWith(server.serveRequest(event.request));
});
```

**Incorrect — assets will not be embedded:**

```ts
addEventListener('fetch', (event: FetchEvent) => {
  // Do NOT do this — createStaticServer is inside the handler
  const server = createStaticServer(staticAssetManifest, {});
  event.respondWith(server.serveRequest(event.request));
});
```

## Asset Manifest

The asset manifest is a TypeScript/JavaScript module mapping URL paths to file metadata. It is consumed by `createStaticServer` at compile time to embed file contents into the WASM binary.

**Automatic generation** — when using `fastedge-build` with `type: 'static'` in `build-config.js`, the manifest is generated automatically as part of the build pipeline. No manual step required. `assetManifestPath` in the config is optional and defaults to `.fastedge/build/static-asset-manifest.js`.

**Manual generation** — when building an HTTP app or needing separate manifests per asset group outside the standard build pipeline, use the `fastedge-assets` CLI directly as a pre-build step:

```sh
npx fastedge-assets ./public ./src/asset-manifest.ts
```

See the ASSETS_CLI reference for the full `fastedge-assets` reference including config fields, content type customization, and manifest structure.

### Multiple Manifests

A single entry point can use multiple static servers, each from a separate manifest. All `createStaticServer` calls must remain at the top level.

```sh
npx fastedge-assets ./images    src/images-manifest.ts
npx fastedge-assets ./styles    src/styles-manifest.ts
npx fastedge-assets ./templates src/templates-manifest.ts
npx fastedge-build -i src/index.ts -o dist/app.wasm -t tsconfig.json
```

```ts
import { createStaticServer } from '@gcoredev/fastedge-sdk-js';
import { staticAssetManifest as imagesManifest }    from './images-manifest.js';
import { staticAssetManifest as stylesManifest }    from './styles-manifest.js';
import { staticAssetManifest as templatesManifest } from './templates-manifest.js';

const imageServer    = createStaticServer(imagesManifest,    { routePrefix: '/images' });
const styleServer    = createStaticServer(stylesManifest,    { routePrefix: '/styles' });
const templateServer = createStaticServer(templatesManifest, {});

addEventListener('fetch', (event: FetchEvent) => {
  const { pathname } = new URL(event.request.url);
  if (pathname.startsWith('/images/')) {
    event.respondWith(imageServer.serveRequest(event.request));
  } else if (pathname.startsWith('/styles/')) {
    event.respondWith(styleServer.serveRequest(event.request));
  } else {
    event.respondWith(
      templateServer
        .serveRequest(event.request)
        .then((r) => r ?? new Response('Not found', { status: 404 })),
    );
  }
});
```

## v1 → v2 Migration

Version 2.x replaced the two-step `createStaticAssetsCache` + `getStaticServer` pattern with a single `createStaticServer` call.

| Area                | v1.x                                          | v2.x                                       |
| ------------------- | --------------------------------------------- | ------------------------------------------ |
| API                 | `createStaticAssetsCache` + `getStaticServer` | `createStaticServer`                       |
| Multiple manifests  | Not supported                                 | Supported — one server per manifest        |
| Read file as string | Not available                                 | `server.readFileString(path)`              |
| Manifest file name  | `static-server-manifest.js`                   | `static-asset-manifest.js` (by convention) |

**v1.x pattern:**

```ts
import { getStaticServer, createStaticAssetsCache } from '@gcoredev/fastedge-sdk-js';
import { staticAssetManifest } from './build/static-server-manifest.js';
import { serverConfig }        from './build-config.js';

const staticAssets = createStaticAssetsCache(staticAssetManifest);
const staticServer = getStaticServer(serverConfig, staticAssets);

async function handleRequest(event) {
  const response = await staticServer.serveRequest(event.request);
  if (response != null) {
    return response;
  }
  return new Response('Not found', { status: 404 });
}

addEventListener('fetch', (event) => event.respondWith(handleRequest(event)));
```

**v2.x pattern:**

```ts
import { createStaticServer } from '@gcoredev/fastedge-sdk-js';
import { staticAssetManifest } from './build/static-asset-manifest.js';
import { serverConfig }        from './build-config.js';

const staticServer = createStaticServer(staticAssetManifest, serverConfig);

async function handleRequest(event) {
  const response = await staticServer.serveRequest(event.request);
  if (response != null) {
    return response;
  }
  return new Response('Not found', { status: 404 });
}

addEventListener('fetch', (event) => event.respondWith(handleRequest(event)));
```

If you used `fastedge-init` to scaffold your project, re-running `npx fastedge-init` updates the generated `static-index.js` entry point automatically.

## See Also

- ASSETS_CLI — `fastedge-assets` reference for manifest generation and config fields
- BUILD_CLI — `fastedge-build` reference including `type: 'static'` build config
- INIT_CLI — `fastedge-init` for scaffolding a static site project
- SDK_API — runtime API reference for HTTP handler entry points
