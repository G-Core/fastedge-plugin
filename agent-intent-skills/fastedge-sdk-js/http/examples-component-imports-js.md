# Synthesis Instructions: examples-component-imports-js.md

> For shared output format, cross-referencing rules, extraction rules, accuracy constraints, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-component-imports-js.md`

## Example-specific extraction hints
- Source: `FastEdge-sdk-js/examples/component-imports` — a TypeScript app that serves embedded images and, with `?w=<width>`, a thumbnail made by a Rust Wasm component (`image` crate)
- **Exception to the base exclusions:** include the `components` entry of `.fastedge/build-config.js` and the WIT interface (`thumbnail.wit`) — without them the import cannot be understood. Still exclude the rest of the project setup
- API focus: `import { dimensions, resize } from 'example:image/thumbnail'` — imported by WIT interface name, called synchronously
  - `dimensions(image: Uint8Array): Size` — reads only the header; cheap
  - `resize(image: Uint8Array, options: Options): Uint8Array` — `Options` is `{ maxWidth: number, format: 'jpeg' | 'png' }`
  - Signatures must match the WIT in the source (WIT `record` fields become camelCase, `enum` becomes a string union, `list<u8>` becomes `Uint8Array`, `result` errors are thrown)
- Common patterns (pull from the example):
  1. **Check size before expensive work** — `dimensions()` first, reject with 413 over `MAX_PIXELS`, only then `resize()`
  2. **Error handling** — one try/catch around the component calls; the component's message is in `error.payload`; respond 415
  3. **Input validation** — `w` must be a whole number (400 otherwise), then clamped to 16–800
- Gotchas:
  - **Request budget** — component work counts against each request's time and memory limits (free plan: 100 ms, 52 MB). Keep the README's measured numbers: ~0.5 MP is comfortable; a 12 MP photo is not
  - **Progressive JPEGs decode ~3× slower** than baseline ones
  - **Data is copied** into the component on each call
  - **Image source** — the example embeds images as static assets to stay self-contained; a real service would `fetch()` the original and pass the same bytes to the component
  - **The `.wasm` component is committed** so builds need no Rust toolchain; rebuilding it needs Rust with the `wasm32-wasip2` target
  - **Requires `@gcoredev/fastedge-sdk-js` 2.7.0 or later**
- Related: the component imports reference (types, errors, what components may import), the build CLI reference, the static sites reference
