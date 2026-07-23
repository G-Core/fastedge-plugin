# Synthesis Instructions: init-cli.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/init-cli.md`

## Audience
AI agents helping developers scaffold new FastEdge projects.

## Output goal
A concise reference for the interactive scaffold wizard. Agents use this to understand what `fastedge-init` creates so they can guide users through project setup or explain the generated files.

## Required sections (in this order)

1. **Usage** — `npx fastedge-init` (no flags — interactive only). Note this is a wizard, not a one-shot command.

2. **HTTP handler setup** — What the wizard asks, what files it creates, and the generated config structure (`fastedge-build.config.json` contents for http-handler type).

3. **Static website setup** — What the wizard asks (additional prompts for static config), what files it creates, and the generated config structure. Note the extra fields compared to HTTP handler.

4. **Generated files** — Table showing all files created for each app type, with brief description of each file's purpose.

5. **Post-scaffolding** — The build command to run after scaffolding (`npx fastedge-build -c fastedge-build.config.json`). For static sites, do NOT instruct users to run `fastedge-assets` manually — manifest generation is automatic when using `type: 'static'` with `fastedge-build`.

## What to exclude
- Build flag details (that's build-cli territory)
- Runtime API details (that's sdk-api territory)
- Deployment instructions (that's deploy skill territory)
- Internal implementation of the wizard

## Quality bar
The generated file list and config structure must match what the actual CLI produces. Cross-reference against `init.ts`, `http-handler.ts`, `static-site.ts`, and `create-config.ts`.
