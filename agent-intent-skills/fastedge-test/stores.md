# Synthesis Instructions: stores.md

> For shared cross-referencing rules, accuracy constraints, and exclusions see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/test/reference/stores.md`

## Audience
AI agents helping developers seed, inspect and test an app's cache and Edge KV locally.

## Source file
`docs/STORES.md`

## Output goal
The reference for local stores: where the data lives, how to seed it, how it behaves over time, and how tests and the debugger use it. Follow the source's section order.

## Required sections (in this order)

1. **Overview** — the cache (one bucket per `dc`, and how the bucket is chosen) and Edge KV (read-only, by store name) that apps see locally; shared by every app, debugger and test process using the same storage service; what store calls return when stores are off
2. **Where the Data Lives** — the stores root, the fixture folder, what is kept between runs
3. **Seeding with Fixtures** — the Edge KV and cache fixture formats, each with a JSON example; load errors
4. **Time and Expiry** — TTLs and the pausable clock
5. **Storage Trace** — what a store call records and where it shows
6. **Storage Explorer** — what it edits; saving back to fixtures
7. **Stores in Tests** — the default (each test gets its own stores), `stores: false`, a shared `createStores()` instance, with one example
8. **Local KV and a Real KV Store** — export a real store into a fixture, seed a real store from a fixture, attach the store to the app, limits
9. **Differences from the Edge** — every difference the source lists

## What to exclude
- Test framework functions other than the stores options (belongs in test-framework.md)
- Server REST endpoints for stores (belongs in server-api.md)
- Debugger panels other than Storage and the Storage Explorer (belongs in vscode-debugger.md)

## Quality bar
The existing file at `plugins/gcore-fastedge/skills/test/reference/stores.md` sets the quality bar. Keep every fixture format, limit and edge difference the source documents.
