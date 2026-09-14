# DocusaurusMCP

An MCP (Model Context Protocol) server for Docusaurus.
Allows AI assistants to remotely manage Docusaurus documentation.

## Features

- **List Documents** — List all Markdown/MDX files in the docs directory
- **Read Documents** — Read the full content of documentation pages
- **Write Documents** — Create or update Markdown/MDX documents
- **Search Documentation** — Full-text search across all documents
- **Rebuild Site** — Trigger Docusaurus builds and update the live site

## Architecture

| Container | Role |
|---|---|
| `docusaurusmcp-backend` | Core MCP server (port 9750) |
| `docusaurusmcp-beacon` | Beacon auto-registration sidecar |
| `docusaurusmcp-proxy` | OIDC + hash authentication proxy |

## Connection Methods

- **Public URL** — External access via hash authentication
- **Docker Network** — Direct connection from AI assistants on the same server
- **Beacon** — Automatic MCP tool registration and aggregation
