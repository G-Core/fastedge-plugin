# Synthesis Instructions: mcp-server-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/mcp-server-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [typescript]
capabilities: [mcp, hono, model-context-protocol, tools]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/mcp-server
```

## Example-specific extraction hints
- This is a TypeScript-only blueprint — the `tsconfig.json` from the source example must be included verbatim under `Files to Create`, and the build script must use the transpile-then-WASM pattern: `tsc` then `fastedge-build --input build/index.js --output build/<name>.wasm --tsconfig tsconfig.json`
- New dependencies to declare in `Dependencies to Add`: `"@hono/mcp": "^0.2.5"`, `"@modelcontextprotocol/sdk": "^1.29.0"`, `"hono": "^4.12.12"`, `"zod": "^4.3.6"`, plus dev dep `"typescript": "^5.9.2"`
- Extract the two-file edge handler split: `src/index.ts` mounts the MCP transport on a Hono route; `src/server.ts` defines the `McpServer` instance and `server.registerTool(...)` calls
- Preserve the transport pattern: `import { StreamableHTTPTransport } from '@hono/mcp'` — call out explicitly that this is the HTTP streaming transport (NOT stdio, NOT raw SSE), wired into Hono at `router.all('/mcp', ...)` so a single endpoint handles all MCP verbs
- Show the canonical handler shape inside the route: `const transport = new StreamableHTTPTransport(); await server.connect(transport); return transport.handleRequest(c);`
- Preserve the tool-registration pattern with zod schemas: `server.registerTool(name, { title, description, inputSchema: z.object({ ... }) }, async (args) => ({ content: [{ type: 'text', text }] }))` — the two `get-alerts` / `get-forecast` tools are the canonical examples
- Preserve the outbound-fetch pattern in tool handlers (`fetch(NWS_API_BASE + ...)` with a `User-Agent` header) and the `makeNWSRequest<T>` helper as the typed-fetch boilerplate
- Include the `src/types.ts` module from the source example verbatim — it carries the response type definitions that the tool handlers depend on
- Preserve `addEventListener('fetch', (event: FetchEvent) => event.respondWith(router.fetch(event.request)))` as the Hono → FastEdge bridge
- Build Notes: must mention the two-step build (`npm run transpile && npm run build-wasm`) and that `main`/`bin` in package.json point at the transpiled `build/` output, not `src/`
- "When to Use" hint: user wants to expose tools to MCP-capable LLM clients (Claude Desktop, Claude Code, Cursor, etc.) from a FastEdge worker — running the Model Context Protocol over HTTP at the edge with zod-validated tool schemas
