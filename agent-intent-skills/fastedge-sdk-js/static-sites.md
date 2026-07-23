# Synthesis Instructions: static-sites.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/static-sites.md`

## Audience
AI agents helping developers build and deploy static websites on FastEdge.

## Output goal
A complete reference for the static site workflow and `createStaticServer` API. Agents use this to generate correct static site code and config — they need to understand the Wizer constraint and server config options.

## Required sections (in this order)

1. **How it works** — Brief explanation of the embedding model: assets are embedded into the WASM binary via Wizer pre-initialization. This is not a traditional file-serving server.

2. **Quick start workflow** — Step-by-step: scaffold → configure → build → deploy. Reference `fastedge-init` for scaffolding and `fastedge-build` for compilation.

3. **Build config fields** — Static-site-specific fields in `BuildConfig`: asset directory, cache config, etc. Table format with field | type | default | description.

4. **Server config** — Complete `ServerConfig` interface: all fields with types, defaults, and descriptions. Must match `create-static-server.ts` defaults exactly.

5. **createStaticServer API** — Function signature, parameter types, return type. Include code examples showing basic usage and custom configuration.

6. **Critical constraint: top-level initialization** — `createStaticServer()` MUST be called at the top level of the module (not inside `addEventListener`). Explain why: Wizer pre-initialization captures the server state at init time.

7. **Asset manifest** — For `type: 'static'` builds, manifest generation is **automatic** — the build pipeline calls `createStaticAssetsManifest()` before compilation. The `fastedge-assets` CLI exists only for **manual/standalone** manifest generation outside the build pipeline. `assetManifestPath` in the config is optional (defaults to `.fastedge/build/static-asset-manifest.js`). Do NOT instruct users to run `fastedge-assets` manually when using the standard `fastedge-build` pipeline.

8. **v1 → v2 migration** — If the source material covers a migration path, include the key changes.

## What to exclude
- General CLI flag details (that's build-cli territory)
- Runtime API details unrelated to static sites (that's sdk-api territory)
- Asset manifest CLI details (that belongs in the build CLI reference, referenced briefly here)

## Quality bar
`ServerConfig` fields and `createStaticServer` return type are the most critical. Must match type declarations. The Wizer constraint must be stated clearly and prominently — getting this wrong causes silent failures.
