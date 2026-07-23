# Synthesis Instructions: quickstart-as.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/quickstart-as.md`

## Audience
AI agents onboarding new AssemblyScript developers to FastEdge — guiding them from zero to a deployed first CDN filter.

## Output goal
A linear, copy-pasteable getting-started guide for CDN apps in AssemblyScript. Agents use this to walk users through their first FastEdge CDN app. Every command and code snippet must work as-is against the documented SDK version.

## Required sections (in this order)

1. **Prerequisites** — Node.js 18+, npm or pnpm. One line each.

2. **Create a new project** — `mkdir`, `npm init -y`. Install `@gcoredev/proxy-wasm-sdk-as` plus `assemblyscript` and `@assemblyscript/wasi-shim` as devDeps. Add the three `asbuild` scripts to `package.json` (debug, release, combined).

3. **First CDN app** — Complete entry-point snippet (`assembly/index.ts`) demonstrating:
   - The required `export * from "@gcoredev/proxy-wasm-sdk-as/assembly/proxy"` (must be the first line — see base rule)
   - A `RootContext` subclass with `createContext`
   - A `Context` subclass overriding all four lifecycle hooks (request/response × headers/body), each logging via the SDK `log` function
   - `registerRootContext` call
   Include a brief table mapping each piece to its purpose, plus a lifecycle-hook table covering the four `on*` methods with their signatures.

4. **Logging note** — One short subsection: use the SDK `log` function with `LogLevelValues.{info,warn,error,debug}`. `console.log` is not available in the wasm environment.

5. **Error handling note** — One short subsection: AssemblyScript does not support `try/catch` in most contexts; check return values instead. Show the empty-string check pattern for `getEnv` (per base rule — empty string, not null).

6. **asconfig.json** — Full config with `extends` (wasi-shim), `targets.debug` and `targets.release`, and the mandatory `options.use: "abort=abort_proc_exit"`. Brief table of required fields. Note that `abort_proc_exit` is required for unhandled aborts to terminate the wasm module correctly.

7. **tsconfig.json (IDE only)** — Brief: this file exists for editor type recognition (`u32`, `usize`, `bool`, `i32`, `f64`), not consumed by `asc`. Show the minimal config.

8. **Build** — The three `npm run asbuild*` commands and where each output lands. Note which binary to deploy (release).

9. **Next steps** — Bullet list referencing related topics by descriptive name only:
   - SDK API reference — full lifecycle hooks, return enums, header/body/property manipulation, FastEdge host APIs (env, secrets, KV store, utils)
   - The examples directory in the SDK repository — standalone reference apps for headers, geo-blocking, JWT, KV store, and more

## What to exclude
- Detailed lifecycle hook matrix beyond the four `on*` methods shown in the entry point (that's sdk-api territory)
- Full host API surface (env, secrets, KV details beyond the import line)
- Project structure deep dive
- Build internals

## Quality bar
The entry-point snippet must compile against the documented SDK version. The `export * from "...proxy"` line must be the first line, before all imports (per base rule). All AssemblyScript types in signatures (`u32`, `usize`, `bool`) must be preserved exactly — never substituted with TypeScript primitives. The asconfig.json must include the mandatory `abort_proc_exit` use directive. The empty-string convention for `getEnv` must be respected — never document a null check.
