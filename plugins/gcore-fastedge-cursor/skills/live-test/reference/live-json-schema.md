# `.live.json` Schema — Live-Test Assertion Block

A `.live.json` file sits beside a `.test.json` fixture. Its only purpose is to declare what a successful live-test run should look like — assertions that the live HTTP response and edge logs satisfy. The fixture itself (`.test.json`) is unchanged; live-test pairs them by basename.

```
fixtures/
├── happy-path.test.json    # request shape (unchanged)
├── happy-path.live.json    # this file: assertions only
├── germany.test.json
└── germany.live.json
```

If a `.live.json` is missing, live-test runs the scenario in **print-only mode** — actual response is shown, no pass/fail. Add the sibling to enable assertions.

---

## Top-Level Shape

```json
{
  "expected": {
    "status": 200,
    "headers": { "x-experiment": "variant-a" },
    "noHeaders": ["x-internal-debug"],
    "body": "exact match string",
    "bodyContains": "substring",
    "contentType": "application/json",
    "json": { "result": "ok" },
    "logs": ["matched experiment", "responded with variant"],
    "noLogs": ["error", "panic"]
  }
}
```

All fields under `expected` are **optional**. Include only what's relevant for the scenario. An `expected: {}` block runs zero assertions but suppresses the print-only warning — only do that if you genuinely don't want to assert (rare; usually you should delete the `.live.json` instead).

---

## Field Reference

### `status`

```json
"status": 200
```

Integer. Exact equality on the response status code. No range support — for "any 2xx", use multiple scenarios or check explicitly.

### `headers`

```json
"headers": {
  "x-experiment": "variant-a",
  "set-cookie": ["session=abc; Path=/", "tracking=def; Path=/"],
  "cache-control": { "contains": "max-age" }
}
```

Per-header assertion. Header names are case-insensitive. Values are matched as:

| Value form | Match |
|---|---|
| `"string"` | Exact equality. For multi-valued headers, treats them as joined or expects single value. |
| `["a", "b"]` | Strict array equality. Use for headers that genuinely return multiple values like `Set-Cookie`. |
| `{ "contains": "..." }` | Substring containment. Use when the value has dynamic parts (timestamps, IDs, etc.). |

If a header is listed in `headers` but absent in the response → assertion fails.

### `noHeaders`

```json
"noHeaders": ["x-debug", "x-internal-token"]
```

List of header names that **must be absent** in the response. Useful for verifying that internal-only headers are stripped before traffic leaves the edge.

### `body`

```json
"body": "Hello World!"
```

Exact equality on the response body. Whitespace and trailing newlines matter — copy the exact bytes. For anything but the simplest fixed responses, prefer `bodyContains` or `json`.

### `bodyContains`

```json
"bodyContains": "experiment-id-42"
```

Substring match against the response body. Single string. For multiple substrings, list them as a single concatenated value or use `json` if the body is JSON.

### `contentType`

```json
"contentType": "application/json"
```

Case-insensitive substring match against the `Content-Type` response header. Equivalent to `headers: { "content-type": { "contains": "application/json" } }` but more readable for the common case.

### `json`

```json
"json": {
  "ok": true,
  "user": { "id": 42 }
}
```

Parse the response body as JSON and assert each key-value pair in the partial matches. Nested objects are checked recursively. Extra keys in the actual response are allowed (this is partial match, not exact). Arrays are matched by exact equality.

If the body is not valid JSON, the assertion fails with a parse error.

### `logs`

```json
"logs": ["request entered hook", "experiment assigned: variant-a"]
```

List of substrings. Live-test scopes the log query to **this scenario's request only** by passing the request's `traceparent` (W3C trace ID, captured from the response header) as the `request_id` filter on `GET /fastedge/v1/apps/{id}/logs`. For each substring in the list, assert at least one returned log entry contains it.

Per-request scoping means the assertion is immune to cross-traffic pollution — other scenarios in the sweep, production traffic on the app, prior debug iterations all live in the same log buffer but only entries from *your* request are evaluated.

Logs come from `log(...)` / `println!()` calls in the WASM app. They are NOT visible in the HTTP response — they're an out-of-band channel surfaced through the FastEdge logs API.

For this assertion to work, the app must have `debug:true` set during the run (live-test does this automatically via the `enable-app-http` / `attach-app-to-cdn-rule-*` workflows). If the run takes longer than the 30-min debug window, scenarios in the tail may run with debug already disabled and the scoped log query will return zero entries — see SKILL.md Step 8 notes.

### `noLogs`

```json
"noLogs": ["panic", "error", "stack trace"]
```

List of substrings that must **not** appear in any log entry **for this scenario's request** (same `request_id`-scoped query as `logs`). Useful for verifying the app didn't take an error path even when the response looks healthy.

---

## Worked Examples

### CORS preflight passes

```json
{
  "expected": {
    "status": 204,
    "headers": {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": { "contains": "GET" }
    },
    "noHeaders": ["x-debug"]
  }
}
```

### A/B experiment assigns variant A

```json
{
  "expected": {
    "status": 200,
    "headers": {
      "x-experiment-name": "homepage-redesign",
      "x-experiment-variant": "A"
    },
    "logs": ["assigned variant A"],
    "noLogs": ["error"]
  }
}
```

### JSON API returns expected shape

```json
{
  "expected": {
    "status": 200,
    "contentType": "application/json",
    "json": {
      "ok": true,
      "user": { "country": "DE" }
    }
  }
}
```

### Error path is taken when env missing

```json
{
  "expected": {
    "status": 500,
    "bodyContains": "configuration error",
    "logs": ["EXPERIMENT_NAME env var not set"]
  }
}
```

---

## Anti-Patterns

❌ **Don't** copy the entire response body into `body` for non-fixed responses. Anything with timestamps, IDs, or dynamic content makes the assertion brittle. Use `bodyContains` or `json`.

❌ **Don't** assert on every header. Stick to the headers your app actually sets or strips — assertions on headers like `Date`, `Server`, `Connection` will break when CDN config changes.

❌ **Don't** use `logs` as a substitute for in-process testing. The HTTP-observable log assertion is for verifying *external* observability — that the app emitted the diagnostic message you expect operators to see. For verifying internal control flow, use `/gcore-fastedge:test` instead.

❌ **Don't** author `expected: {}` to silence warnings. If you don't want to assert, delete the `.live.json` and let print-only mode run. The empty block looks intentional but communicates nothing.
