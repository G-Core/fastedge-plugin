# Inference Reference — Detect Scenarios from Source

This reference is consumed by `/gcore-fastedge:debug` (the `--infer` mode) and `/gcore-fastedge:live-test` (to know what scenarios should exist). It tells the agent how to look at a FastEdge project and produce a structured list of scenarios worth testing.

The output of inference is a single in-memory structure (described at the end of this file). Both consuming skills act on that structure — `debug --infer` writes fixtures, `live-test` checks coverage.

---

## Inference Output Schema

Inference always produces this shape:

```json
{
  "appType": "proxy-wasm" | "wasi-http",
  "language": "assemblyscript" | "rust" | "javascript",
  "hooks": ["on_request_headers", "on_request_body", "on_response_headers", "on_response_body"],
  "env": [
    { "name": "EXPERIMENT_NAME", "required": true,  "branches": ["with-experiment", "without-experiment"] },
    { "name": "VARIANT_A_PATH",  "required": true,  "branches": ["variant-a", "variant-b"] }
  ],
  "secrets": [
    { "name": "API_KEY", "required": true }
  ],
  "properties": [
    { "name": "country", "branches": ["germany", "united-states", "default"] },
    { "name": "client.ip" }
  ],
  "scenarios": [
    {
      "name": "happy-path",
      "description": "Base case — required env present, no branch conditions matched",
      "env": {},
      "request": { "path": "/", "headers": {} },
      "expected": {
        "logs": ["onRequestHeaders >> Hello World!", "onResponseHeaders >> Hello World!"]
      }
    },
    {
      "name": "germany",
      "description": "country property = DE",
      "env": {},
      "request": { "path": "/", "headers": {} },
      "properties": { "country": "DE" },
      "expected": {
        "logs": ["matched country: DE"],
        "status": 302,
        "headers": { "location": { "contains": "/de" } }
      }
    }
  ],
  "testSeeds": ["happy-path", "missing-env", "germany"]
}
```

`scenarios` is the concrete list `debug --infer` writes as `*.test.json` files. `scenarios[].expected` is the assertion block `live-test --infer` writes as `*.live.json` siblings. `testSeeds` is the list of test-case names harvested from `tests/*.test.ts` (if present) — duplicates with `scenarios.name` are merged.

---

## Step 1: App Type & Language Detection

Mirror the convention already documented in the debug skill body. Concrete signals:

| Signal                                                     | App Type     | Language         |
| ---------------------------------------------------------- | ------------ | ---------------- |
| `Cargo.toml` contains `proxy-wasm` dependency              | `proxy-wasm` | `rust`           |
| `asconfig.json` exists at project root                     | `proxy-wasm` | `assemblyscript` |
| `Cargo.toml` contains `wstd` or `fastedge` (no proxy-wasm) | `wasi-http`  | `rust`           |
| `package.json` build script invokes `fastedge-build`       | `wasi-http`  | `javascript`     |

If signals conflict or none match, ask the user before continuing — do not guess.

---

## Step 2: Hook Detection

Proxy-wasm apps declare hooks as class methods or trait impls. Wasi-http apps have a single request handler (not multi-hook) — for those, hooks always reduce to `["request"]`.

### AssemblyScript (proxy-wasm)

Search `assembly/index.ts` (or whatever the entry is in `asconfig.json`) for class members:

```ts
onRequestHeaders(...)      → on_request_headers
onRequestBody(...)         → on_request_body
onResponseHeaders(...)     → on_response_headers
onResponseBody(...)        → on_response_body
onLog(...)                 → on_log
```

A hook is reportable if its body does anything observable — calls `log(...)`, reads/writes headers, mutates body, calls `get_property` / `set_property`, dispatches `httpCall`, etc. The only case to skip is a hook whose entire body is a single `return Continue` / equivalent — truly empty passthrough. A hook that only logs IS reportable: logging is the behavior the developer wants to verify (see `helloWorld` example).

### Rust (proxy-wasm)

Search the entry crate for `impl HttpContext for ...` blocks. Same hook names with `on_` snake_case as method names. Same passthrough rule.

### JavaScript / TypeScript (wasi-http)

Always `["request"]`. Look for the default exported handler (typically in `src/index.ts` or `src/index.js`).

---

## Step 3: Env Var Detection

| Language          | Pattern                                                  | Capture |
| ----------------- | -------------------------------------------------------- | ------- |
| AssemblyScript    | `getEnv("X")` or `getEnv('X')`                           | `X`     |
| Rust (proxy-wasm) | `get_property(vec!["env", "X"])` or `std::env::var("X")` | `X`     |
| Rust (wasi-http)  | `std::env::var("X")`                                     | `X`     |
| JavaScript        | `getEnv("X")` (from FastEdge SDK) or `process.env.X`     | `X`     |

For each captured name, determine **required** by checking whether the code path proceeds without a value (e.g. provides a default via `||`, `??`, `.unwrap_or`, `os.environ.get` with default → optional). If the access is unguarded → required.

For each captured name, find **branches**: search for `if (X` / `match X` / `if X ==` patterns in the same scope. Each distinct comparison is a branch. Name branches descriptively — `with-X`, `without-X`, or use the literal value being compared (`X-set-to-staging`).

---

## Step 4: Secret Detection

| Language       | Pattern                                                    |
| -------------- | ---------------------------------------------------------- |
| AssemblyScript | `getSecret("X")`                                           |
| Rust           | `get_secret("X")` (FastEdge SDK helpers)                   |
| JavaScript     | `getSecret("X")`                                           |

Always treat secrets as **required**. Branches based on secret values are rare; report them only if present.

---

## Step 5: Property Reads

Properties expose the platform's per-request state — geo, client IP, scheme, host, etc.

| Language               | Pattern                                         | Notes                              |
| ---------------------- | ----------------------------------------------- | ---------------------------------- |
| AssemblyScript         | `get_property("X")` or `get_property(["X"])`    | Property name in the call          |
| Rust                   | `self.get_property(vec!["X"])`                  | Property path may be multi-segment |
| JavaScript (wasi-http) | Properties not directly exposed in the same way | Skip for wasi-http                 |

Common property names to recognize and treat as branchable:

| Property         | Branchable values                                           |
| ---------------- | ----------------------------------------------------------- |
| `country`        | 2-letter country codes (DE, US, GB, ...)                    |
| `client.ip`      | Specific IPs only if literal comparison found               |
| `request.scheme` | `http`, `https`                                             |
| `request.host`   | Specific hosts only if literal comparison found             |
| `request.method` | GET, POST, PUT, DELETE, ...                                 |
| `request.path`   | Path patterns; usually NOT branched on (handled by routing) |

For `country` specifically, generate one scenario per country code that appears in source comparisons, plus a `default` scenario (no comparison match).

---

## Step 6: Conditional Branches

After Steps 3–5 identify named symbols, look for control flow that gates on those symbols. The branches you produce as scenarios are the **distinct outcomes**, not every if-statement.

Heuristic order:

1. **Country branches dominate**: if `country` is read and compared, generate one scenario per matched value + a default
2. **Required env var branches**: each env var that is required and compared gets `with-VALUE` scenarios for each compared value
3. **Optional env vars**: generate `with-X` and `without-X` scenarios
4. **Secrets**: usually only `with-secret` and `missing-secret` (the latter to verify error handling)
5. **Method branches**: if `request.method` is compared, generate one scenario per compared method
6. **Header-presence branches**: if a specific request header is checked for presence (`if (header === "")`, `if (X-API-Key)`, etc.), generate `with-HEADER` and `without-HEADER` scenarios. Common in CORS, auth, and feature-flag apps.
7. **Header-value branches**: if a request header is compared to specific values, generate one scenario per compared value (e.g. `origin-allowed`, `origin-blocked` for CORS).
8. **Body branches**: if request body content is inspected (e.g. redaction patterns), generate `with-pattern` and `without-pattern` scenarios

Stop adding scenarios when the cross-product gets larger than ~8. Beyond that, scenarios are no longer manually meaningful — the developer should pick which combinations matter.

---

## Step 7: Test-Case Seed Mining (Optional)

If `tests/` exists with `*.test.ts` files using `defineTestSuite`, harvest the test names as scenario seeds:

1. Read each test file
2. Extract suite descriptions and `it(...)` / `test(...)` names
3. Convert to kebab-case scenario names (e.g. "Allows GET on /api" → `allows-get-on-api`)
4. Add to `testSeeds` list in the output

These are informational only — `debug --infer` does NOT generate fixtures from test seeds (the test runner is in-process and its scenarios use a different schema). They surface in `live-test` to suggest where `.live.json` siblings should also be authored.

---

## Step 8: Scenario Naming Conventions

- All lowercase, hyphen-separated, no `.test.json` suffix in the `name` field (the suffix is added when writing the file)
- Maximum length 32 chars
- Avoid generic names like `test1`, `scenario-a` — they fail the readability check
- Reserved names that consumer skills recognize:
  - `happy-path` — the base case, no branch conditions matched
  - `missing-env` — required env var unset (forces error path)
  - `missing-secret` — required secret unset
  - `default` — country/property branch fallback

---

## Step 9: Assertion Inference (for `.live.json`)

`/gcore-fastedge:live-test --infer` uses inference output to draft `expected` blocks for each scenario. Only **filter-derivable** assertions are emitted — things the WASM filter directly produces. Origin-derivable values (status when traffic passes through, content-type from origin, JSON shape, etc.) are out of scope and stay for the developer to add manually after reviewing the draft.

**Note on framing — wasi-http vs proxy-wasm**: the "filter-derivable" framing above is proxy-wasm-centric (the filter sits in front of an origin). For **wasi-http apps**, the WASM IS the origin — there is no upstream to pass through to. Every `Response` constructor in the handler is statically derivable. Walk all return paths in the request handler and emit per-path `status` / `body` / `headers` / `contentType`. For wasi-http, the only non-derivable values are responses that wrap an outbound-fetch result (where upstream content flows through verbatim) and bodies built from runtime data — see "What is NOT emitted" below.

For each scenario, walk the hooks the scenario's branch reaches and emit:

### `logs` — from `log(...)` calls

Every `log(...)` call reachable on the scenario's branch becomes one substring entry in `logs[]`. Use the literal log message. If the message is built dynamically (e.g. `log(LogLevel.info, "got " + value)`), emit the static prefix only (`"got "`) — never invent the dynamic portion.

| Language | Pattern | Captured substring |
|---|---|---|
| AssemblyScript (proxy-wasm) | `log(LogLevelValues.X, "msg")` | `"msg"` |
| Rust (proxy-wasm) | `info!("msg")`, `log::info!("msg")`, `proxy_wasm::log("msg")` | `"msg"` |
| Rust (wasi-http) | `println!("msg")`, `print!("msg")` | `"msg"` |
| JavaScript | `console.log("msg")` | `"msg"` |

**Skip `eprintln!` / `eprint!` for Rust wasi-http apps.** Only stdout is captured by the FastEdge platform — stderr output is silently dropped. Any substring inferred from a stderr macro will always FAIL the assertion. This is the wasi-http analog of the `onLog` skip rule for proxy-wasm. (Source: `FastEdge-sdk-rust/CLAUDE.md` Platform Constraints.)

Emit the substring exactly as authored — `"onRequestHeaders >> Hello World!"` not `"hello world"`. The assertion is substring match, so longer literal strings are fine.

A hook whose only behavior is `log(...)` and `Continue` IS reachable on every scenario by default (no branch gates the hook itself). Multi-hook apps with no branching produce one `logs` entry per hook.

**Skip `onLog` / `on_log` for CDN/proxy-wasm apps.** The `proxy_on_log` lifecycle hook is not dispatched on FastEdge for proxy-wasm filters — neither in the `fastedge-test` debugger nor at the edge. Any `log(...)` calls inside an `onLog()` (AS) or `fn on_log(&mut self)` (Rust) method never appear in edge logs and would always FAIL the assertion. Inference must walk the four request-flow hooks only (`onRequestHeaders`, `onRequestBody`, `onResponseHeaders`, `onResponseBody`) when emitting `logs[]` substrings for proxy-wasm projects. Rationale: see `context/PLUGIN_SKILL_FINDINGS.md` finding #13. This skip is proxy-wasm-only — wasi-http apps do not have an analogous lifecycle hook, so the rule does not apply there.

### `status` and `body` — from short-circuit / local-response calls

When the filter short-circuits with a fixed status code, that's a deterministic assertion target.

| Language | Pattern | Capture |
|---|---|---|
| AssemblyScript (proxy-wasm) | `stream_context.sendLocalResponse(403, "Forbidden", ...)` | `status: 403`, `body: "Forbidden"` |
| Rust (proxy-wasm) | `self.send_http_response(403, vec![...], Some(b"Forbidden"))` | same |
| Rust (wasi-http) | `Response::builder().status(N).body(Body::from("literal"))` | `status: N`, `body: "literal"` |
| Rust (wasi-http) | `Response::builder().status(N).body(Body::empty())` | `status: N` |
| JavaScript (Web Response) | `new Response(body, { status: N, headers: {...} })` | `status: N`, `body: <static>` if literal, `headers: {...}` (static keys/values only) |
| JavaScript (Web Response) | `new Response(body)` — no init | `status: 200` (Web default), `body: <static>` if literal |
| JavaScript (Web Response) | `Response.redirect(url, status?)` | `status: <status or 302>`, `headers: { location: <url> }` if URL literal |
| JavaScript (Hono) | `c.text(body, status?)` / `c.html(body, status?)` / `c.body(body, status?)` | `status: <status or 200>`, `body: <static>` if literal; `contentType: "text/plain"` for `c.text`, `"text/html"` for `c.html` |
| JavaScript (Hono) | `c.json(obj, status?)` | `status: <status or 200>`, `contentType: "application/json"`, `json: <obj>` if obj is a literal |
| JavaScript (Hono) | `c.redirect(url, status?)` | `status: <status or 302>`, `headers: { location: <url> }` if URL literal |

For wasi-http apps the response constructor is the entire response — walk every return path in the handler and emit per-path captures. If multiple return paths produce different responses (e.g. `if (!env) return new Response("err", {status:500}); return new Response(...)`), each path becomes its own scenario's `expected` block (see Per-scenario branching).

If the body is built dynamically, emit `bodyContains` with the static prefix only. If the body is unknown at static analysis (e.g. constructed from runtime data, or wrapping `await fetch(...).body`), omit `body`/`bodyContains` entirely.

### `headers` and `noHeaders` — from response header mutations

| Pattern | Becomes |
|---|---|
| AS (proxy-wasm): `stream_context.headers.response.add("X-Powered-By", "FastEdge")` | `headers: { "x-powered-by": "FastEdge" }` |
| AS (proxy-wasm): `stream_context.headers.response.set("X", "Y")` | same |
| AS (proxy-wasm): `stream_context.headers.response.remove("X-Internal")` | `noHeaders: ["x-internal"]` |
| Rust (proxy-wasm): `self.set_http_response_header("X", Some("Y"))` | `headers: { "x": "Y" }` |
| Rust (proxy-wasm): `self.set_http_response_header("X", None)` | `noHeaders: ["x"]` |
| Rust (wasi-http): `Response::builder().header("X", "Y")` | `headers: { "x": "Y" }` |
| JavaScript: `response.headers.set("X-Foo", "bar")` | `headers: { "x-foo": "bar" }` |
| JavaScript: `new Response(body, { headers: { "x-foo": "bar" } })` | `headers: { "x-foo": "bar" }` |
| JavaScript: `response.headers.delete("X-Foo")` | `noHeaders: ["x-foo"]` |
| Hono (JS): `c.header("X-Foo", "bar")` | `headers: { "x-foo": "bar" }` |

Header names are normalized to lowercase before emission. Only emit when the value is a static string. For dynamic values, emit `headers: { "x": { "contains": "<static-prefix>" } }` if the prefix is non-empty, otherwise omit that header.

### What is NOT emitted

**For proxy-wasm apps** — values that flow through from origin when the filter doesn't short-circuit:

| Field | Why not |
|---|---|
| `status` (when no short-circuit) | Comes from origin — origin-derivable, out of scope |
| `body` (general response body) | Origin echoes through |
| `contentType` | Comes from origin |
| `json` | Origin response shape |

**For wasi-http apps** — these four fields ARE emitted when the `Response` constructor's arguments are static (see status/body table above). The non-derivable cases are:

| Field | Why not |
|---|---|
| `body` from outbound-fetch passthrough | e.g. `new Response((await fetch(upstream)).body)` — body is the upstream response, not the handler's |
| Dynamic literal segments in body / headers | Use `bodyContains` with the static prefix only (existing dynamic-body rule) |

**For both app types**:

| Field | Why not |
|---|---|
| `noLogs` | No reliable static signal that an error path is *prevented* — false positives if the developer added defensive logs |

The developer adds these manually if they want to assert on them. The inferred file is a **starting point** — the live-test SKILL warns the developer to review the draft before running.

### Per-scenario branching

When inference produces multiple scenarios from Step 6 branch detection, each scenario's `expected` reflects only the branch that scenario takes. Worked example: `cors` has a preflight-OPTIONS branch that calls `sendLocalResponse(204, ...)` with CORS headers; the non-preflight branch falls through. The `preflight-options` scenario gets `status: 204` plus the CORS headers; `happy-path` gets only the `logs` assertion (no short-circuit on this branch).

If branch detection is ambiguous and a single fixture can't be mapped to a single branch, emit only the `logs` reached on every branch (the intersection) and surface a NOTE in the live-test output recommending the developer split the scenario or refine the fixture.

---

## Step 9.5: Fixture-as-Signal — Enrich Assertions from Existing Fixtures

If `fixtures/` already contains hand-authored `*.test.json` files (i.e. the developer has scenarios in place before `--infer` runs), treat each fixture's content as an additional inference input. Source-only inference (Step 9) is the floor; fixture content steers branch selection and supplies literal values that source alone can't enumerate (dynamically-keyed env reads, header-value branches without literal comparisons in source, per-scenario env subsets).

This step applies to **both proxy-wasm (CDN) and wasi-http (HTTP) projects** — the signals differ slightly per fixture format, but the principle is identical: developer-authored fixtures encode intent that inference can leverage.

**This step strictly enriches Step 9 output. It does NOT invent assertions that source doesn't support.**

### Step 9.5a: Read each existing fixture as a branch selector

For each `*.test.json` in `fixtures/`, the following fields are inference signals — they tell us which source branch this scenario exercises:

| Fixture field | Inference signal |
|---|---|
| `request.headers["x-foo"]: "Y"` | Scenario takes the branch where this header has value `Y`. Use `Y` as the literal value for any header-keyed env read or comparison in source. |
| `request.method: "POST"` | Scenario takes the POST branch (only if source has a method-specific branch; otherwise just request shape). |
| `request.body: "..."` | Scenario takes the populated-body branch. If source inspects body for a pattern, this is the matched-pattern scenario. |
| `properties["request.country"]: "DE"` (CDN only) | Scenario takes the country=DE property branch. Same mechanic as header-value but for proxy-wasm `get_property` reads (Step 5). |
| `dotenv` block absent OR `{ enabled: false }` | Scenario tests env-unset behavior. Emit the source's missing-env error path (status + body from `if (!env)` guards). |
| `dotenv.path: "./variant-a"` | Scenario uses the variant-a env subset. Read `fixtures/variant-a/.env` for that scenario's literal env values. |

The fixture's `description` field is informational only — don't derive assertions from it. The structured fields above are the signals.

### Step 9.5b: Cross-reference `fixtures/.env` for literal values

When source has a dynamically-keyed env read (e.g. `getEnv(country)` where `country` is a runtime value), look up the literal in `fixtures/.env` using the matching fixture field as the key:

- Fixture has `headers["geoip-country-code"]: "DE"`, source has `getEnv(country)`, `.env` has `FASTEDGE_VAR_ENV_DE=https://de.example.com/` → emit `headers: { location: { contains: "https://de.example.com/" } }` if source returns via `Response.redirect`, or `bodyContains: "https://de.example.com/"` if the URL is embedded in body.
- Fixture has `headers["geoip-country-code"]: "FR"`, no `FASTEDGE_VAR_ENV_FR` in `.env` → fall through to source's fallback path. If fallback uses BASE_ORIGIN and `.env` has `FASTEDGE_VAR_ENV_BASE_ORIGIN=https://default.example.com/`, emit that as the location.
- Fixture has `properties["request.country"]: "DE"` (CDN), source compares country property and reads per-country `getEnv(country)`, `.env` has matching key → same enrichment as the header case.

Use `{ contains: "<value>" }` for header values that may be embedded in larger strings; use exact equality only when the source emits the value verbatim.

### Step 9.5c: Schema impact

When fixture-as-signal is applied, the inference output's `scenarios[]` array reflects the union of source-derived and fixture-derived branches:

- Source-derived scenarios with no matching fixture stay as drafts (developer can author a fixture later or leave the scenario unmaterialised).
- Fixture-named scenarios that don't directly map to a source branch use fixture content + source pattern-matching to pick the closest branch.
- Both kinds of scenarios produce richer `expected` blocks via 9.5a + 9.5b than they would under Step 9 alone.

Live-test's basename-match rule (`scenario.name ↔ fixture-basename.test.json`) is unchanged — fixture-as-signal just makes the matched scenarios stronger.

### Step 9.5d: Don't do this

- **Don't fabricate assertions from fixture alone.** If a fixture sets a field but source has no corresponding branch, do not emit a fixture-only assertion. The scenario just uses the source's fallback path.
- **Don't propagate fixture errors silently.** If a fixture references a value with no `.env` entry AND no source fallback exists, surface a NOTE — don't guess.
- **Don't override Step 9.** Source-derived assertions (filter logs, short-circuit status/body, header mutations) always emit. Fixture-as-signal only ADDS to the expected block.
- **Don't read fixtures recursively.** Only top-level `fixtures/*.test.json` and `fixtures/.env` (plus per-variant subdir `.env` when `dotenv.path` points at one). Don't traverse into other directories.

---

## Inference Quality Bar

A scenario list is "good enough" when:

1. Every detected hook is exercised by at least one scenario
2. Every required env var has at least one scenario where it is set
3. Every conditional branch identified in Step 6 has a corresponding scenario
4. The list is between 1 and ~8 scenarios — bigger lists usually mean the heuristic over-fired

If the inferred list violates any of these, reduce or expand and re-check before producing fixtures.

---

## Worked Example: `cors` (proxy-wasm-sdk-as)

Source: `assembly/index.ts` reads `getEnv("ALLOWED_ORIGINS")` and `getEnv("EXPOSE_HEADERS")`. `onRequestHeaders` checks for `Origin` header and OPTIONS preflight method. `onResponseHeaders` injects CORS headers.

Inference output:

- `appType: "proxy-wasm"`, `language: "assemblyscript"`
- `hooks: ["on_request_headers", "on_response_headers"]`
- `env: [{ name: "ALLOWED_ORIGINS", required: true, branches: ["wildcard", "specific-origin"] }, { name: "EXPOSE_HEADERS", required: false }]`
- `properties: []` (no get_property calls beyond passthrough)
- Scenarios: `happy-path`, `preflight-options`, `wildcard-origin`, `specific-origin-match`, `specific-origin-mismatch`

Five scenarios — within the quality bar, each branch covered.

---

## Worked Example: `geo-redirect` (FastEdge-sdk-js)

Source: `src/index.js` reads `getEnv("BASE_ORIGIN")` (required, errors with 500 if missing) and `getEnv(<country-code>)` keyed off `request.headers.get("geoip-country-code")`. Returns `Response.redirect(redirectOrigin, 302)` on the happy path.

Project ships with 4 hand-authored fixtures (`fallback.test.json` with FR, `germany.test.json` with DE, `missing-config.test.json` with no `dotenv` block, `us.test.json` with US) plus `fixtures/.env` containing:

```
FASTEDGE_VAR_ENV_BASE_ORIGIN=https://default.example.com/
FASTEDGE_VAR_ENV_DE=https://de.example.com/
FASTEDGE_VAR_ENV_US=https://us.example.com/
```

Common detected fields:

- `appType: "wasi-http"`, `language: "javascript"`, `hooks: ["request"]`
- `env: [{ name: "BASE_ORIGIN", required: true }]` (the country-keyed `getEnv(country)` is dynamic — Step 3 captures `BASE_ORIGIN` as the only literal env name)
- `secrets: []`, `properties: []`

### Source-only output (Step 9, no fixtures present)

Source has no literal country comparisons (the country code flows directly into `getEnv(country)` without a value-equality branch), so Step 6 generates only generic branches:

- Scenarios: `happy-path` (no country header), `with-country-header` (header present, generic), `missing-config` (BASE_ORIGIN unset)
- `expected` blocks:
  - `happy-path` → `{ "status": 302 }` — dynamic location is omitted
  - `with-country-header` → `{ "status": 302 }` — same; country-keyed env value also dynamic
  - `missing-config` → `{ "status": 500, "body": "BASE_ORIGIN environment variable is not set" }` — both literals derive from source

### Source + Fixture-as-Signal output (Step 9 + 9.5)

Step 9.5 reads the 4 existing fixtures, treats each as a branch selector (9.5a), and cross-references `fixtures/.env` for literal redirect targets (9.5b). Each fixture becomes its own scenario with enriched `expected`:

- `germany` (from `germany.test.json`) → `{ "status": 302, "headers": { "location": { "contains": "https://de.example.com/" } } }`
  - 9.5a: fixture sets `geoip-country-code: DE` → DE branch
  - 9.5b: `.env` has `FASTEDGE_VAR_ENV_DE=https://de.example.com/` → location enriched
- `us` (from `us.test.json`) → same shape with `https://us.example.com/`
- `fallback` (from `fallback.test.json`, FR header) → `{ "status": 302, "headers": { "location": { "contains": "https://default.example.com/" } } }`
  - 9.5a: fixture sets `geoip-country-code: FR` → FR branch
  - 9.5b: no `FASTEDGE_VAR_ENV_FR` in `.env` → fall through to BASE_ORIGIN → location enriched with the BASE_ORIGIN value
- `missing-config` (from `missing-config.test.json`) → `{ "status": 500, "body": "BASE_ORIGIN environment variable is not set" }`
  - 9.5a: fixture has no `dotenv` block → unset-env branch → match the source's error path

All four scenarios get strong assertions when fixture-as-signal is applied. The dev can review and tighten further (e.g. swap `contains` for exact equality, add `noHeaders` for stripped values).

Without Step 9.5, the `germany` / `us` / `fallback` fixtures would either get only `{ "status": 302 }` (source-only baseline) or `{ "logs": [] }` intersection-only (if basename matching falls through). Step 9.5 is what turns this into a useful validation suite.

---

## What Inference Does NOT Do

- **Does not parse the source into a full AST.** Regex/grep over the entry file is enough for the patterns above. Anything more sophisticated is over-engineering.
- **Does not infer origin-derivable assertions** (status when traffic passes through, content-type from origin, JSON body shape, `noLogs`). Step 9 covers only filter-derivable assertions. The developer adds origin-dependent assertions manually after reviewing the inferred `.live.json`.
- **Does not run the project.** No build, no test execution. Pure static reading.
- **Does not modify source files.** Read-only inference. (It does write fixtures and `.live.json` siblings into the project — the consuming skills do that — but nothing under `assembly/`, `src/`, or other source directories.)
