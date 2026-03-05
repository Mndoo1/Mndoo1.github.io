# Distributed Architecture Migration Guide

This guide covers how to migrate from a single-server setup to a distributed
3-server architecture using AWS and Tailscale.

## Architecture Overview

| Server   | Role     | Services                        | AWS Instance |
|----------|----------|---------------------------------|--------------|
| AWS 1    | Brain    | MongoDB, LiteLLM, Datadog      | t3.micro*    |
| AWS 2    | Executor | OpenClaw, MCP Filesystem        | t3.medium    |
| AWS 3    | Scout    | Browserless Chrome (Scraping)   | t3.medium    |

*AWS 1 can be downgraded to t3.micro after migration since it only runs the
database and API gateway.

## Credits Estimate

- **AWS 1 ($100 credit):** Running t3.micro with DB-only workload can last
  approximately 6 months.
- **AWS 2 and AWS 3 ($200 credit each):** Running t3.medium comfortably lasts
  approximately 6.5 months.

## Prerequisites

Each server needs:
- Docker and Docker Compose installed
- Tailscale installed and connected to the same tailnet

## Step 1 — Configure AWS 1 (Brain)

The Brain server stores the database and routes AI requests. If you are
migrating from an existing single-server setup, stop the current system first:

```bash
cd ~/ai_environment
docker-compose down
```

Then deploy the new lightweight configuration:

```bash
cd ~/ai_environment
cp /path/to/brain/docker-compose.yml .
cp /path/to/brain/.env.example .env
# Edit .env with your actual API keys
nano .env
docker-compose up -d
```

Note the Tailscale IP of this server (referred to as `BRAIN_IP` below).

## Step 2 — Configure AWS 3 (Scout)

The Scout server handles browser-based scraping. Set it up before the Executor
because the Executor needs the Scout IP.

```bash
mkdir ~/scout_architecture && cd ~/scout_architecture
cp /path/to/scout/docker-compose.yml .
docker-compose up -d
```

Note the Tailscale IP of this server (referred to as `SCOUT_IP` below).

## Step 3 — Configure AWS 2 (Executor)

The Executor runs the main AI agent. It connects to the Brain for database and
LLM routing, and to the Scout for browser access.

```bash
mkdir ~/executor_architecture && cd ~/executor_architecture
cp /path/to/executor/docker-compose.yml .
cp /path/to/executor/.env.example .env
```

Edit `.env` and replace the placeholder IPs:

```
MONGO_URL=mongodb://<BRAIN_IP>:27017
AI_ROUTER_URL=http://<BRAIN_IP>:4000
BROWSER_WS_ENDPOINT=ws://<SCOUT_IP>:3000
```

Then start the services and fix permissions:

```bash
docker-compose up -d
sudo chown -R 1000:1000 ~/executor_architecture
```

## Step 4 — Connect AnythingLLM

Open AnythingLLM on your local machine and set the MCP endpoint to the
Executor's Tailscale IP:

```
http://<EXECUTOR_IP>:8080
```

## How It Works

- **Data Safety:** All data lives on AWS 1 (Brain). Even if AWS 2 or AWS 3
  crash, your data remains safe.
- **Chat History:** OpenClaw on AWS 2 connects to MongoDB on AWS 1, so
  existing chat history and memory are preserved automatically.
- **Resource Efficiency:** AWS 1 has minimal load (database only), while AWS 2
  gets full 4 GB RAM dedicated to the AI agent.
