# Synthesis Instructions: sdk-reference-as.md

> For shared output format, cross-referencing rules, extraction rules, accuracy constraints, and exclusions see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference-as.md`

## Source
`docs/SDK_API.md` — generated from the SDK's AssemblyScript source code

## Extraction hints
- Source is a pre-generated markdown API reference for the entire SDK
- Preserve all type signatures, enum values, and import paths exactly as documented
- This is a CDN-only SDK — all content relates to proxy-wasm CDN app development
- Two import paths: `@gcoredev/proxy-wasm-sdk-as/assembly` (core) and `assembly/fastedge` (FastEdge extensions)
- Key sections to preserve: proxy-wasm lifecycle, RootContext/Context classes, lifecycle hooks, return enums, stream_context header manipulation, body/buffer/property functions, FastEdge host APIs (getEnv, getSecret, KvStore, getCurrentTime, setLogLevel)
- Mark deprecated functions clearly (getEnvVar, getSecretVar, getSecretVarEffectiveAt)
