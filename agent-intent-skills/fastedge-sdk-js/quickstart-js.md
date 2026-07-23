# Synthesis Instructions: quickstart-js.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/quickstart-js.md`

## Audience
AI agents onboarding new FastEdge developers — helping them go from zero to deployed app.

## Output goal
A linear, copy-pasteable getting-started guide. Agents use this to walk users through their first FastEdge app. Every command and code snippet must work as-is.

## Required sections (in this order)

1. **Prerequisites** — Node.js >= 20, npm/pnpm. One line each, no elaboration.

2. **Install** — `npm install -g @gcoredev/fastedge-sdk-js` (or project-local install variant)

3. **Two paths** — Brief fork:
   - **Scaffold with fastedge-init** — `npx fastedge-init`, what it asks, what it creates (2-3 sentences, link to init-cli for details)
   - **Build directly** — For existing projects, `npx fastedge-build` with flags (2-3 sentences, link to build-cli for details)

4. **First app example** — Complete, runnable HTTP handler (~15 lines) demonstrating:
   - FetchEvent listener pattern
   - `getEnv()` usage
   - `getSecret()` usage
   - `KvStore` usage (at least one method)
   - Returning a Response

5. **Build and deploy** — The two commands: `npx fastedge-build -c fastedge-build.config.json` then deploy via Gcore panel or API (brief mention, link to deploy skill for details).

6. **Next steps** — Bullet list referencing related topics by descriptive name (see cross-referencing rules in base — never use filenames or file links):
   - SDK API reference — full runtime API for env, secrets, KV, and fetch
   - Build CLI reference — all build flags and config options
   - Init CLI reference — scaffold wizard details
   - Static sites guide — serve static websites from FastEdge

## What to exclude
- Exhaustive API reference (that's sdk-api territory)
- All CLI flags (that's build-cli territory)
- Static site deep dive (that's static-sites territory)
- Architecture or internals explanation
- Troubleshooting

## Quality bar
The first app example is the most critical section. It must compile and run on the current SDK version. All import specifiers must use `fastedge::` paths. All API calls must match `types/` declarations.
