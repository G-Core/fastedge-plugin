# Shared Reference Document Instructions

This file contains shared instructions for all reference document intent skills in this directory. Each intent skill references this file for universal rules.

## Audience
AI agents answering developer questions about FastEdge capabilities and usage patterns in AssemblyScript.

## Output format

Structured Markdown with **no YAML frontmatter** (except where the intent skill explicitly requires a frontmatter block). Concise, decision-dense — not a tutorial. Agents use this to explain concepts and suggest code patterns. When frontmatter **is** required, the language tag for AssemblyScript documents must be `assemblyscript` (not `as`).

## Cross-referencing rules

- **Never output file links or filenames** as cross-references (e.g. `[SDK_API](SDK_API.md)` or `./sdk-reference-as.md`). These reference documents live in different skill directories so relative links will not resolve.
- Instead, use **descriptive topic terms** that an agent can use to discover the relevant reference — e.g. "the SDK API reference", "the KV store reference".
- In "See Also", "Next Steps", or "Related" sections, use plain-text topic descriptions with an em-dash explanation — e.g. `- SDK API reference — full lifecycle hooks and enum values`.

## Code formatting rules

- **All code blocks must use fenced code blocks** with the `typescript` language tag. Never include raw unfenced code — it renders poorly and is inconsistent with other reference pages.
- **Inline code containing backticks** must use double-backtick spans so the inner backticks render correctly.
- Source material sections that include file contents must wrap each file in its own fenced code block with the correct language tag.

## General extraction rules

- Focus on **API usage patterns**, not project structure
- Extract idiomatic AssemblyScript patterns (explicit types, null checks, ArrayBuffer decoding)
- For CDN patterns: note which proxy-wasm lifecycle hooks are involved
- **Preserve exact type signatures** from authoritative sources. AssemblyScript types (`u32`, `usize`, `bool`, `f64`, `u64`, `ArrayBuffer`, `string`) must not be replaced with standard TypeScript types (`number`, `boolean`, `Buffer`, `String`). SDK-defined types (`Headers`, `HeaderPair`, `WasmResultValues`, `FilterHeadersStatusValues`, `FilterDataStatusValues`, `BufferTypeValues`, `LogLevelValues`) must also be preserved exactly — never substitute `string[][]` for `Headers` or `Uint8Array` for `ArrayBuffer`.
- Include type information where available
- Content must be useful to **any AI coding tool**, not just Claude Code (MCP constraint R-007)

## Accuracy constraints

- **Type fidelity**: Return types, parameter types, and generic bounds must exactly match the authoritative source declarations. Never simplify `ArrayBuffer | null` to just `ArrayBuffer`.
- **Signatures come from declarations, not call sites**: Derive function return types and parameter types from the **function declaration** (e.g. `export function set_property(...): WasmResultValues`), never from how examples happen to call the function. Examples often ignore return values, which does not mean the return type is `void`.
- **Nullability matters**: If an API returns `ArrayBuffer | null`, the output must document both the found case and the `null`/not-found case.
- **Empty-string convention**: This SDK uses empty string — not `null` — for "not found" returns. `getEnv`, `getSecret`, `getSecretEffectiveAt`, and `headers.request.get` all return `string`, never `string | null`. Document the empty-string check pattern (`value.length === 0` or `value == ""`), not null checks. Only document `| null` when the source declaration explicitly includes it (e.g. `KvStore.open(): KvStore | null`, `KvStore.get(): ArrayBuffer | null`).
- **Signature completeness**: Every parameter and its type must appear in documented signatures.
- **No invented APIs**: Only document functions, methods, and classes that exist in the source. Do not infer or extrapolate APIs that are not declared.
- **Import path consistency**: There are exactly two consumer-facing import paths: `@gcoredev/proxy-wasm-sdk-as/assembly` (core) and `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge` (FastEdge extensions). Never use sub-paths like `assembly/fastedge/kvStore` or `assembly/runtime`.
- **Snippet validity**: Code snippets must respect documented runtime constraints and lifecycle rules. Request-time APIs must be shown inside the appropriate lifecycle hook. Never write a snippet that contradicts a constraint stated in the same section.
- **Export-first convention**: `export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy"` must appear as the **first line** in any entry-point snippet, before all imports. This matches every source example and is required for the host to bind the proxy-wasm ABI exports.

## What to exclude

- Project structure, package.json, asconfig.json, build config (that belongs in the blueprint)
- Complete file listings
- Installation instructions
- Marketing language
