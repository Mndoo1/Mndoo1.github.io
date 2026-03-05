# Mndoo1.github.io

## Distributed Architecture

This repository contains the Docker Compose configurations for a 3-server
distributed setup:

| Directory  | Server   | Purpose                              |
|------------|----------|--------------------------------------|
| `brain/`   | AWS 1    | MongoDB, LiteLLM API Gateway, Datadog|
| `executor/`| AWS 2    | OpenClaw AI Agent, MCP Filesystem    |
| `scout/`   | AWS 3    | Browserless Chrome for Scraping      |

See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) for full setup instructions.