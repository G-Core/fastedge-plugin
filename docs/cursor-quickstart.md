# Cursor Quickstart

## Prerequisites

- [Cursor CLI](https://cursor.com/docs/cli/installation) installed
- Docker running locally
- A Gcore account with FastEdge activated
- A Gcore API key from the [Gcore portal](https://portal.gcore.com/api-keys)

The plugin starts `ghcr.io/g-core/fastedge-mcp-server:latest` on demand. The
container provides the FastEdge build toolchains and API client.

## Configure Credentials

Cursor CLI inherits environment variables from its shell:

```bash
export GCORE_API_KEY="your-api-key"
export GCORE_API_BASE="https://api.gcore.com"
```

On macOS, Cursor launched from Finder or the Dock does not normally inherit
variables exported from `.zshrc`. Set them in the GUI session, then fully quit
and reopen Cursor:

```bash
launchctl setenv GCORE_API_KEY "your-api-key"
launchctl setenv GCORE_API_BASE "https://api.gcore.com"
```

The marketplace and plugin manifests contain no credentials. The plugin passes
the two variables by name to the MCP Docker container.

## Personal Installation

Add the GitHub repository as a Cursor marketplace:

```bash
agent plugin marketplace add https://github.com/G-Core/fastedge-plugin.git
```

To test a particular branch, tag, or commit, add `--git-ref <ref>`.

Start Cursor CLI:

```bash
agent
```

Enter `/plugin`, open the **Marketplace** tab, select **Gcore FastEdge**, and
install it at user or project scope. Cursor currently installs the plugin
interactively after the marketplace has been registered.

## Team Installation

Cursor Teams and Enterprise administrators can distribute the plugin from the
same GitHub repository:

1. Open **Dashboard → Plugins**.
2. Select **Add Marketplace → Import from Repo**.
3. Enter `https://github.com/G-Core/fastedge-plugin`.
4. Configure access groups and choose Default Off, Default On, or Required.

Team marketplace import is a Teams/Enterprise feature. Personal marketplaces use
the CLI flow above.

## Verify the Installation

List registered marketplaces:

```bash
agent plugin marketplace list
```

Open a FastEdge project in Cursor and ask:

```text
How does the FastEdge KV store work?
```

The plugin should load FastEdge documentation through its MCP server. Docker
should show a running `ghcr.io/g-core/fastedge-mcp-server` container after the
first tool call.

## Update or Remove

```bash
agent plugin marketplace update gcore-fastedge-marketplace
agent plugin marketplace remove gcore-fastedge-marketplace
```

Use `/plugin` to manage the installed plugin itself.

## Troubleshooting

- **`GCORE_API_KEY is required`**: the key did not reach the Cursor process.
  Configure it before launching Cursor and restart the application.
- **`401 Invalid API token`**: replace the expired or invalid API key, then
  restart Cursor so the MCP container receives the new value.
- **`403 FastEdge ... is not fully activated`**: the key is valid, but FastEdge
  is not enabled for the account. Contact the account administrator.
- **MCP server not starting**: verify Docker is running and can pull from
  `ghcr.io`.
- **Wrong MCP server starts**: check for another `fastedge-assistant` entry in
  personal Cursor MCP configuration and rename the duplicate.
