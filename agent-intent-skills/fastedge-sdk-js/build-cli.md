# Synthesis Instructions: build-cli.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/build-cli.md`

## Audience
AI agents helping developers compile their FastEdge applications to WASM binaries.

## Output goal
A complete CLI flag reference and config format guide. Agents use this to generate correct `fastedge-build` commands and `fastedge-build.config.json` files — not to understand the compilation internals.

## Required sections (in this order)

1. **Usage** — Basic invocation (`npx fastedge-build [flags]`) and the two modes: direct flags vs config-driven (`-c config.json`)

2. **CLI flags table** — Complete table: flag | alias | type | default | description. Must match `arg()` definitions in `build.ts` exactly.

3. **Config-driven builds** — `BuildConfig` interface with all fields, types, and descriptions. Show a complete example config file. Key accuracy on `type` field:
   - TypeScript interface declares `type?: BuildType` (optional) because direct-flags mode never uses it
   - In **config-driven mode**, `type` is **effectively required** — if omitted or invalid, the build errors with "Invalid config type"
   - There is NO default — it does not fall back to `'http'`
   - Valid values: `'http'` | `'static'` (must match the switch statement in `config-build.ts`)
   - Document as: "Required in config-driven mode. Optional only when using direct CLI flags (`-i`/`-o`)."

4. **Build types** — Table of the two supported build types (`http`, `static`) with brief description of what each produces. Must match the switch statement in `config-build.ts`. Note: the enum values are `'http'` and `'static'` (not `'http-handler'` or `'static-website'`).

5. **Static-only fields** — `AssetCacheConfig` interface fields that only apply to static site builds. All fields are **optional** via `Partial<AssetCacheConfig>`. Include all cache control options. Key accuracy:
   - `assetManifestPath` defaults to `.fastedge/build/static-asset-manifest.js` when omitted — it is NOT required
   - For `type: 'static'` builds, manifest generation is **automatic** (called by the build pipeline before compilation) — the `fastedge-assets` CLI is only needed for standalone/manual manifest generation outside the build pipeline

6. **Build pipeline overview** — Brief (3-5 bullet) description of what happens: esbuild → Wizer → JCO. Not a deep dive — just enough for agents to explain what the output `.wasm` file contains. When components are configured, add one bullet: the components are linked into the output and the build checks every import left in it.

6a. **Component imports** — the repeatable `--component <interface>=<path>` flag and the `components` config field (`Record<string, string>`, WIT interface name → component file), one example of each, and the generated `fastedge-components.d.ts` (written next to the entry file; deleted again by a build without components if the build generated it). Requires `@gcoredev/fastedge-sdk-js` 2.7.0 or later. Defer types, errors and limits to "the component imports reference" — do not repeat them here.

7. **Output** — What the build produces (component WASM binary), default output path, how to customize. Include `--output` with a single `--config`: the config is built as usual but written to the given path instead of `wasmOutput` (2.7.0 or later), with the source's example and its error for more than one `--config`.

## What to exclude
- How to install the SDK (that's quickstart territory)
- Runtime API details (that's sdk-api territory)
- Static server API details (that's static-sites territory)
- Internal pipeline implementation details beyond the brief overview

## Quality bar
The flag table is the most critical section. Every flag must appear, with the correct alias, type, and default — including `--component`. Cross-reference against `build.ts` `arg()` call.
