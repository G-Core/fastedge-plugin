<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: 81145a9a43ec499240c687bd49376ab20c72b11c
      updated: 2026-08-20
-->

---
type: feature
app_type: http
languages: [typescript]
capabilities: [mcp, hono, model-context-protocol, tools]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/mcp-server
---

# Blueprint: MCP Server (TypeScript)

Expose Model Context Protocol (MCP) tools from a FastEdge HTTP worker. Suitable when the goal is to serve MCP-capable LLM clients (Claude Desktop, Claude Code, Cursor, etc.) directly from the edge, with zod-validated tool schemas and full outbound fetch access.

## When to Use

- User wants to run an MCP server on FastEdge so that LLM clients can discover and call tools over HTTP.
- User needs to register named tools with typed input schemas (via zod) and return structured content responses.
- User wants stateless, edge-hosted MCP endpoints with zero infrastructure.

## Two-File Architecture

This blueprint splits handler concerns across two source files:

| File | Role |
|---|---|
| `src/index.ts` | Edge entry point. Mounts the MCP StreamableHTTPTransport on a Hono route. Bridges Hono to the FastEdge fetch event. |
| `src/server.ts` | MCP server definition. Creates the `McpServer` instance and registers all tools via `server.registerTool(...)`. |

## Files to Create

### `src/index.ts`

```typescript
import { StreamableHTTPTransport } from '@hono/mcp';
import { Hono } from 'hono';

import server from './server.js';

const router = new Hono();

router.all('/mcp', async (c) => {
  const transport = new StreamableHTTPTransport();
  await server.connect(transport);
  return transport.handleRequest(c);
});

addEventListener('fetch', (event: FetchEvent) => {
  event.respondWith(router.fetch(event.request));
});
```

**Key patterns:**
- `StreamableHTTPTransport` from `@hono/mcp` is the HTTP streaming transport — NOT stdio, NOT raw SSE. It handles all MCP verbs (initialize, tools/list, tools/call, etc.) on a single endpoint.
- `router.all('/mcp', ...)` registers the endpoint for all HTTP methods, which is required by the MCP HTTP transport spec.
- Canonical handler shape inside the route: `const transport = new StreamableHTTPTransport(); await server.connect(transport); return transport.handleRequest(c);`
- `addEventListener('fetch', (event: FetchEvent) => event.respondWith(router.fetch(event.request)))` is the Hono → FastEdge bridge. Required in every FastEdge HTTP worker.

### `src/server.ts`

```typescript
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';

import type {
  AlertFeature,
  AlertsResponse,
  ForecastPeriod,
  ForecastResponse,
  PointsResponse,
} from './types.js';

const NWS_API_BASE = 'https://api.weather.gov';
const USER_AGENT = 'weather-app/1.0';

// Typed fetch helper — reuse this pattern for all outbound API calls
async function makeNWSRequest<T>(url: string): Promise<T | null> {
  const headers = {
    'User-Agent': USER_AGENT,
    Accept: 'application/geo+json',
  };

  try {
    const response = await fetch(url, { headers });
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    return (await response.json()) as T;
  } catch (error) {
    console.error('Error making NWS request:', error);
    return null;
  }
}

function formatAlert(feature: AlertFeature): string {
  const props = feature.properties;
  return [
    `Event: ${props.event || 'Unknown'}`,
    `Area: ${props.areaDesc || 'Unknown'}`,
    `Severity: ${props.severity || 'Unknown'}`,
    `Status: ${props.status || 'Unknown'}`,
    `Headline: ${props.headline || 'No headline'}`,
    '---',
  ].join('\n');
}

const server = new McpServer({
  name: 'weather',
  version: '1.0.0',
});

server.registerTool(
  'get-alerts',
  {
    title: 'Get Weather Alerts',
    description: 'Get weather alerts for a US state',
    inputSchema: z.object({
      state: z.string().length(2).describe('Two-letter state code (e.g. CA, NY)'),
    }),
  },
  async ({ state }) => {
    const stateCode = state.toUpperCase();
    const alertsUrl = `${NWS_API_BASE}/alerts?area=${stateCode}`;
    const alertsData = await makeNWSRequest<AlertsResponse>(alertsUrl);

    if (!alertsData) {
      return { content: [{ type: 'text', text: 'Failed to retrieve alerts data' }] };
    }

    const features = alertsData.features || [];
    if (features.length === 0) {
      return { content: [{ type: 'text', text: `No active alerts for ${stateCode}` }] };
    }

    const formattedAlerts = features.map(formatAlert);
    const alertsText = `Active alerts for ${stateCode}:\n\n${formattedAlerts.join('\n')}`;
    return { content: [{ type: 'text', text: alertsText }] };
  },
);

server.registerTool(
  'get-forecast',
  {
    title: 'Get Weather Forecast',
    description: 'Get weather forecast for a location',
    inputSchema: z.object({
      latitude: z.number().min(-90).max(90).describe('Latitude of the location'),
      longitude: z.number().min(-180).max(180).describe('Longitude of the location'),
    }),
  },
  async ({ latitude, longitude }) => {
    const pointsUrl = `${NWS_API_BASE}/points/${latitude.toFixed(4)},${longitude.toFixed(4)}`;
    const pointsData = await makeNWSRequest<PointsResponse>(pointsUrl);

    if (!pointsData) {
      return {
        content: [{
          type: 'text',
          text: `Failed to retrieve grid point data for coordinates: ${latitude}, ${longitude}. This location may not be supported by the NWS API (only US locations are supported).`,
        }],
      };
    }

    const forecastUrl = pointsData.properties?.forecast;
    if (!forecastUrl) {
      return { content: [{ type: 'text', text: 'Failed to get forecast URL from grid point data' }] };
    }

    const forecastData = await makeNWSRequest<ForecastResponse>(forecastUrl);
    if (!forecastData) {
      return { content: [{ type: 'text', text: 'Failed to retrieve forecast data' }] };
    }

    const periods = forecastData.properties?.periods || [];
    if (periods.length === 0) {
      return { content: [{ type: 'text', text: 'No forecast periods available' }] };
    }

    const formattedForecast = periods.map((period: ForecastPeriod) =>
      [
        `${period.name || 'Unknown'}:`,
        `Temperature: ${period.temperature || 'Unknown'}°${period.temperatureUnit || 'F'}`,
        `Wind: ${period.windSpeed || 'Unknown'} ${period.windDirection || ''}`,
        `${period.shortForecast || 'No forecast available'}`,
        '---',
      ].join('\n'),
    );

    const forecastText = `Forecast for ${latitude}, ${longitude}:\n\n${formattedForecast.join('\n')}`;
    return { content: [{ type: 'text', text: forecastText }] };
  },
);

export default server;
```

**Key patterns:**
- `McpServer` is imported from `@modelcontextprotocol/sdk/server/mcp.js` (note the `.js` extension required for Node16 module resolution).
- `server.registerTool(name, { title, description, inputSchema }, handlerFn)` is the canonical registration signature. `inputSchema` must be a `z.object(...)` from zod.
- Tool handlers receive validated args (typed by the zod schema) and must return `{ content: [{ type: 'text', text: string }] }`.
- `makeNWSRequest<T>` is the typed outbound fetch helper pattern: generic `T`, `User-Agent` header set, returns `T | null` on error. Adapt for any third-party API.
- Tool handlers must handle null returns from `makeNWSRequest` and return error content rather than throwing.

### `src/types.ts`

Include verbatim — these response type definitions are required by the tool handlers in `server.ts`. Generate this file with the correct interface shapes matching the NWS API (or replace with types for the target API):

```typescript
export interface AlertProperties {
  event?: string;
  areaDesc?: string;
  severity?: string;
  status?: string;
  headline?: string;
}

export interface AlertFeature {
  properties: AlertProperties;
}

export interface AlertsResponse {
  features?: AlertFeature[];
}

export interface PointsProperties {
  forecast?: string;
}

export interface PointsResponse {
  properties?: PointsProperties;
}

export interface ForecastPeriod {
  name?: string;
  temperature?: number;
  temperatureUnit?: string;
  windSpeed?: string;
  windDirection?: string;
  shortForecast?: string;
}

export interface ForecastProperties {
  periods?: ForecastPeriod[];
}

export interface ForecastResponse {
  properties?: ForecastProperties;
}
```

### `tsconfig.json`

Include verbatim:

```json
{
  "compilerOptions": {
    "target": "ES2023",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "./build",
    "rootDir": "./src",
    "strict": true,
    "skipLibCheck": true,
    "lib": ["ES2023"],
    "types": ["@gcoredev/fastedge-sdk-js"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
```

**Constraints:**
- `module` and `moduleResolution` must be `Node16` — required for `.js` extension imports to resolve correctly in ESM output.
- `types: ["@gcoredev/fastedge-sdk-js"]` injects FastEdge globals (`FetchEvent`, etc.) without explicit imports.
- `outDir: "./build"` / `rootDir: "./src"` — transpiled output goes to `build/`, which is what `fastedge-build` consumes.

## Dependencies to Add

### Runtime dependencies

```json
"@gcoredev/fastedge-sdk-js": "^2.3.0",
"@hono/mcp": "^0.2.5",
"@modelcontextprotocol/sdk": "^1.29.0",
"hono": "^4.12.25",
"zod": "^4.3.6"
```

### Dev dependencies

```json
"typescript": "^5.9.2"
```

## `package.json` fields

```json
{
  "type": "module",
  "main": "src/index.ts",
  "bin": {
    "<app-name>": "./build/index.js"
  },
  "scripts": {
    "build": "npm run transpile && npm run build-wasm",
    "build-wasm": "npx fastedge-build --input build/index.js --output build/<name>.wasm --tsconfig tsconfig.json",
    "transpile": "tsc"
  },
  "files": ["build"]
}
```

**Notes:**
- `main` points at `src/index.ts` (TypeScript source, for editor tooling), but `bin` points at `build/index.js` (transpiled output, for execution).
- `"type": "module"` is required for ESM output.

## Build Notes

The build is a two-step process:

1. **Transpile**: `npm run transpile` — runs `tsc`, compiles `src/**/*.ts` to `build/`.
2. **WASM compile**: `npm run build-wasm` — runs `npx fastedge-build --input build/index.js --output build/<name>.wasm --tsconfig tsconfig.json`, which bundles the transpiled JS into a WASM binary for FastEdge.

`npm run build` executes both steps in sequence. The deploy skill uploads the `.wasm` output from `build/`.

Do NOT pass `src/index.ts` directly to `fastedge-build`. The input must be the transpiled `build/index.js`.

## Tool Registration API

### `server.registerTool(name, descriptor, handler)`

| Parameter | Type | Description |
|---|---|---|
| `name` | `string` | Tool identifier. MCP clients use this name to call the tool. |
| `descriptor.title` | `string` | Human-readable display name. |
| `descriptor.description` | `string` | Natural language description used by LLM clients for tool selection. |
| `descriptor.inputSchema` | `z.ZodObject` | Zod schema for input validation. Arguments are validated before the handler is called. |
| `handler` | `async (args: InferredArgs) => ToolResult` | Async function receiving validated args. Must return `{ content: [{ type: 'text', text: string }] }`. |

### `ToolResult` shape

```typescript
{
  content: Array<{
    type: 'text';
    text: string;
  }>;
}
```

All tool return values in this example use `type: 'text'`. MCP also supports `type: 'image'` and `type: 'resource'`, but those are not demonstrated in this example.

## Transport: StreamableHTTPTransport

`StreamableHTTPTransport` from `@hono/mcp` implements the MCP Streamable HTTP transport. It is:
- **Not stdio** — no stdin/stdout piping.
- **Not raw SSE** — wraps the streaming protocol inside HTTP request/response handled by Hono.
- **Single endpoint** — all MCP verbs (initialize, tools/list, tools/call, etc.) are routed through `router.all('/mcp', ...)`.

Each request creates a new transport instance. The sequence is always: `new StreamableHTTPTransport()` → `server.connect(transport)` → `transport.handleRequest(c)`.

## Outbound Fetch Pattern

Tool handlers that call external APIs must set a `User-Agent` header. The typed helper pattern:

```typescript
async function makeRequest<T>(url: string): Promise<T | null> {
  try {
    const response = await fetch(url, {
      headers: { 'User-Agent': 'my-app/1.0', Accept: 'application/json' },
    });
    if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
    return (await response.json()) as T;
  } catch (error) {
    console.error('Error:', error);
    return null;
  }
}
```

Returning `null` on error (rather than throwing) is required — tool handlers must check for null and return a descriptive `content` response instead of propagating exceptions.

## MCP Endpoint

The MCP server listens at `/mcp` on whatever domain the FastEdge app is deployed to. MCP clients configure the server URL as `https://<worker-domain>/mcp`.

## See Also

- fastedge-sdk-js SDK reference (sdk-reference-js)
- Hono framework reference (hono routing, middleware)
- Model Context Protocol specification (MCP HTTP transport, tool registration)
- FastEdge build CLI reference (fastedge-build)
- http-base blueprint (base HTTP worker skeleton)
