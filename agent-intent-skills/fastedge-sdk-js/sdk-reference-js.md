# Synthesis Instructions: sdk-reference-js.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference-js.md`

## Audience
AI agents helping developers use FastEdge runtime APIs in their WASM applications.

## Output goal
A concise, decision-dense API reference. Agents use this to generate correct code that calls FastEdge runtime APIs — they do not need background explanation of how WASM works.

## Required sections (in this order)

1. **Environment Variables** — `getEnv(name)` signature, return type (`string | null`), code example

2. **Secrets** — `getSecret(name)` and `getSecretEffectiveAt(name, effectiveAt)` signatures with return types, note that `effectiveAt` is a `number` (Unix timestamp)

3. **KV Store** — Document `KvStore` static methods and `KvStoreInstance` instance methods in **separate tables** to avoid confusing static factory methods with instance methods. Include every method. Critical accuracy:
   - `KvStore.open(name)` is a **static** factory method — there is no constructor (`new KvStore(...)` does not exist)
   - `get()` returns `ArrayBuffer | null` (NOT string)
   - `scan()` returns `Array<string>` (NOT `Array<ArrayBuffer>`)
   - `zrangeByScore()` / `zscan()` return `Array<[ArrayBuffer, number]>` tuples
   - Code example showing `KvStore.open(name)` pattern

4. **Web APIs** — Table of available standard Web APIs: fetch, Request, Response, Headers, URL, URLSearchParams, TextEncoder/TextDecoder, streams (ReadableStream, WritableStream, TransformStream), crypto, timers (setTimeout, setInterval). Note which are standard-conformant vs have limitations.

5. **FetchEvent** — `request` (Request), `client` (ClientInfo), `respondWith(response)`. Include `ClientInfo` fields (especially `geo: GeoData`).

6. **Headers immutability** — Note that incoming request headers are read-only; explain the pattern for creating modified headers.

7. **Import patterns** — Show the `fastedge::` import specifiers (NOT Node module paths).

## What to exclude
- Installation or build instructions (that's quickstart/build-cli territory)
- Internal SDK implementation details
- StarlingMonkey or runtime internals
- Marketing language or feature highlights

## Quality bar
All type signatures must match the `types/` directory declarations exactly. When in doubt, trust the `.d.ts` files over any prose description.
