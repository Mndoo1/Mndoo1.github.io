
# Distributed Architecture - Security-Hardened Setup Guide

This guide upgrades the original 3-server distributed architecture to a production-grade,
security-hardened deployment designed to run for 6 months on AWS credits.

---

## Security Analysis of Original Setup

The original setup had these critical vulnerabilities:

| Issue | Risk Level | Fix Applied |
|---|---|---|
| MongoDB exposed without authentication | CRITICAL | Added root + app user auth via mongod.conf and mongo-init.js |
| Browserless Chrome open to anyone | CRITICAL | Added TOKEN-based authentication |
| No firewall rules, ports open to internet | CRITICAL | iptables scripts lock ports to Tailscale only |
| Docker images use `:latest` (unpinned) | HIGH | Pinned to specific versions (mongo:7.0, browserless:2.18.0) |
| No resource limits on containers | HIGH | Memory and CPU limits on every container |
| LiteLLM API has no authentication | HIGH | Added LITELLM_MASTER_KEY for API auth |
| No backup strategy for MongoDB | HIGH | Automated backup script with 7-day retention |
| API keys in env vars with typos (`{` vs `${`) | MEDIUM | Fixed all variable references |
| No health checks on services | MEDIUM | Added Docker health checks on all services |
| No SSH hardening | MEDIUM | Disabled password auth, root login, added fail2ban |
| No container security options | MEDIUM | Added read_only, no-new-privileges, tmpfs |
| No Docker network isolation | LOW | Dedicated bridge networks per server |
| No log rotation | LOW | Docker log driver with 10MB max, 3 files |

---

## Cost Optimization for 6 Months

### Credit Breakdown

| Server | Instance | Monthly Cost | Credit | Lasts |
|---|---|---|---|---|
| AWS 1 (Brain) - DB + Router | t3.micro (downgrade after setup) | ~$7.60 | $100 | ~13 months |
| AWS 2 (Executor) - OpenClaw | t3.medium | ~$30.40 | $200 | ~6.5 months |
| AWS 3 (Scout) - Browserless | t3.small (downgrade from medium) | ~$15.20 | $200 | ~13 months |

### Optimization Strategy

1. **AWS 1**: After migration, downgrade to t3.micro ($7.60/mo). MongoDB and LiteLLM
   proxy need minimal RAM. The mongod.conf limits WiredTiger cache to 0.5GB.
2. **AWS 3**: Downgrade to t3.small ($15.20/mo). Browserless with `MAX_CONCURRENT_SESSIONS=5`
   and `PREBOOT_CHROME=true` runs fine on 2GB RAM.
3. **AWS 2**: Keep at t3.medium. OpenClaw needs the 4GB RAM.
4. **All servers**: Resource limits prevent any single container from consuming all RAM
   and causing OOM kills that waste compute time.

---

## Prerequisites (All 3 Servers)

Run these on each new EC2 instance before proceeding:

```bash
# Install Docker
sudo yum update -y
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install Tailscale (private network)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Log out and back in for docker group to take effect
exit
```

---

## Step 1: Harden Each Server (Run on ALL 3 servers)

```bash
# Copy harden-server.sh to the server, then:
chmod +x harden-server.sh
sudo ./harden-server.sh
sudo systemctl restart docker
sudo systemctl restart sshd
```

This script will:
- Configure Docker daemon with security defaults (no inter-container communication, no-new-privileges)
- Disable SSH password authentication (use key-based auth only)
- Disable root SSH login
- Install and configure fail2ban (3 failed SSH attempts = 1 hour ban)
- Enable automatic security updates

---

## Step 2: Setup AWS 1 (Brain - Database and API Router)

### 2.1 Stop Existing System

```bash
cd ~/ai_environment
docker-compose down
```

**Your data is safe.** The MongoDB volume (`mongo_data`) persists even after `docker-compose down`.

### 2.2 Deploy New Configuration

```bash
mkdir ~/brain_architecture
cd ~/brain_architecture

# Copy these files to ~/brain_architecture:
#   - docker-compose.yml    (from aws1-brain/)
#   - mongod.conf           (from aws1-brain/)
#   - mongo-init.js         (from aws1-brain/)
#   - litellm_config.yaml   (from aws1-brain/)

# Create .env from template
cp .env.example .env
nano .env
```

### 2.3 Set Strong Passwords

Edit the `.env` file and replace ALL placeholder values:

```
MONGO_ROOT_USER=admin
MONGO_ROOT_PASS=<generate with: openssl rand -base64 32>

MONGO_APP_USER=moltbot_app
MONGO_APP_PASS=<generate with: openssl rand -base64 32>
MONGO_APP_DB=moltbot

LITELLM_MASTER_KEY=sk-<generate with: openssl rand -hex 24>

DD_API_KEY=<your actual datadog key>
GROQ_API_KEY=<your actual key>
CEREBRAS_API_KEY=<your actual key>
NVIDIA_API_KEY=<your actual key>
```

### 2.4 Migrate Existing Data

If you had a previous MongoDB without authentication, migrate the volume:

```bash
# The old volume name was likely ai_environment_mongo_data
# Check existing volumes:
docker volume ls

# If old volume exists, copy data to new volume:
docker run --rm \
  -v ai_environment_mongo_data:/from:ro \
  -v brain_architecture_mongo_data:/to \
  alpine sh -c "cp -a /from/. /to/"
```

### 2.5 Start Services

```bash
docker-compose up -d

# Verify everything is healthy:
docker-compose ps
docker logs mongodb --tail 20
docker logs litellm_router --tail 20
```

### 2.6 Configure Firewall

```bash
chmod +x ../scripts/firewall-brain.sh
sudo ../scripts/firewall-brain.sh
```

This locks MongoDB (27017) and LiteLLM (4000) to Tailscale network only.

### 2.7 Note the Tailscale IP

```bash
tailscale ip -4
```

Save this as `BRAIN_IP` (e.g., `100.10.10.10`).

---

## Step 3: Setup AWS 3 (Scout - Browserless Scraping)

### 3.1 Deploy Configuration

```bash
mkdir ~/scout_architecture
cd ~/scout_architecture

# Copy docker-compose.yml from aws3-scout/
# Copy .env.example from aws3-scout/
cp .env.example .env
nano .env
```

### 3.2 Set Browserless Token

```bash
# Generate a strong token:
openssl rand -hex 24
```

Put this in the `.env` file as `BROWSERLESS_TOKEN`.

### 3.3 Start Services

```bash
docker-compose up -d
docker logs browserless_scout --tail 10
```

### 3.4 Configure Firewall

```bash
chmod +x ../scripts/firewall-scout.sh
sudo ../scripts/firewall-scout.sh
```

### 3.5 Note the Tailscale IP

```bash
tailscale ip -4
```

Save this as `SCOUT_IP` (e.g., `100.30.30.30`).

---

## Step 4: Setup AWS 2 (Executor - OpenClaw AI)

### 4.1 Deploy Configuration

```bash
mkdir ~/executor_architecture
cd ~/executor_architecture

# Copy docker-compose.yml from aws2-executor/
# Copy .env.example from aws2-executor/
cp .env.example .env
nano .env
```

### 4.2 Configure Connection Details

Edit `.env` with the IPs from previous steps:

```
MONGO_URL=mongodb://moltbot_app:<APP_PASSWORD>@<BRAIN_IP>:27017/moltbot?authSource=moltbot
AI_ROUTER_URL=http://<BRAIN_IP>:4000
BROWSER_WS_ENDPOINT=ws://<SCOUT_IP>:3000?token=<BROWSERLESS_TOKEN>
LITELLM_API_KEY=sk-<your LITELLM_MASTER_KEY from AWS 1>
```

### 4.3 Start Services

```bash
docker-compose up -d
docker logs openclaw_executor --tail 20
```

### 4.4 Configure Firewall

```bash
chmod +x ../scripts/firewall-executor.sh
sudo ../scripts/firewall-executor.sh
```

### 4.5 Fix Permissions

```bash
sudo chown -R 1000:1000 ~/executor_architecture
```

---

## Step 5: Setup Automated Backups (AWS 1)

### 5.1 Install Backup Script

```bash
cd ~/brain_architecture
chmod +x ../scripts/backup-mongodb.sh
```

### 5.2 Schedule Daily Backups

```bash
# Add cron job for daily backup at 3 AM:
(crontab -l 2>/dev/null; echo "0 3 * * * MONGO_ROOT_USER=admin MONGO_ROOT_PASS='YOUR_ROOT_PASS' /home/ec2-user/brain_architecture/../scripts/backup-mongodb.sh >> /var/log/mongo-backup.log 2>&1") | crontab -
```

### 5.3 Test Backup

```bash
MONGO_ROOT_USER=admin MONGO_ROOT_PASS='YOUR_ROOT_PASS' ./scripts/backup-mongodb.sh
ls -la ~/backups/mongodb/
```

---

## Step 6: Verify Full System

### 6.1 Run Health Check

From any server with Tailscale:

```bash
chmod +x scripts/health-check.sh
./scripts/health-check.sh <BRAIN_IP> <EXECUTOR_IP> <SCOUT_IP>
```

### 6.2 Test MongoDB Authentication

```bash
# This should FAIL (no auth):
docker exec mongodb mongosh --eval "show dbs"

# This should SUCCEED (with auth):
docker exec mongodb mongosh -u admin -p 'YOUR_ROOT_PASS' --eval "show dbs"
```

### 6.3 Test Browserless Token

```bash
# This should FAIL (no token):
curl http://<SCOUT_IP>:3000/json/version

# This should SUCCEED (with token):
curl "http://<SCOUT_IP>:3000/json/version?token=<YOUR_TOKEN>"
```

### 6.4 Connect AnythingLLM

Open AnythingLLM on your Mac, go to MCP settings, and connect to:
```
http://<EXECUTOR_TAILSCALE_IP>:8080
```

Your chat history will be intact because OpenClaw connects to the same MongoDB.

---

## Architecture Diagram

```
  Your Mac (AnythingLLM)
        |
        | Tailscale VPN (encrypted)
        |
  AWS 2 (Executor) ----Tailscale----> AWS 1 (Brain)
  t3.medium, 4GB RAM                  t3.micro, 1GB RAM
  - OpenClaw Agent                    - MongoDB (auth enabled)
  - MCP Filesystem                    - LiteLLM Router (key auth)
        |                             - Datadog Agent
        | Tailscale
        |
  AWS 3 (Scout)
  t3.small, 2GB RAM
  - Browserless Chrome (token auth)
```

**All traffic flows through Tailscale VPN. No ports are exposed to the public internet.**

---

## Security Checklist

- [ ] MongoDB authentication enabled with separate root and app users
- [ ] LiteLLM protected with master key
- [ ] Browserless protected with token authentication
- [ ] Firewall rules applied on all 3 servers (ports locked to Tailscale)
- [ ] SSH password auth disabled, key-based only
- [ ] fail2ban running on all servers
- [ ] Docker images pinned to specific versions
- [ ] Container resource limits set
- [ ] Container security options (no-new-privileges, read_only) applied
- [ ] Automated daily MongoDB backups configured
- [ ] Docker log rotation configured (10MB max, 3 files)
- [ ] Automatic OS security updates enabled
- [ ] All .env files have strong randomly generated passwords (openssl rand)

---

## Maintenance Schedule

| Task | Frequency | Command |
|---|---|---|
| Check health | Daily | `./scripts/health-check.sh BRAIN EXEC SCOUT` |
| Verify backups | Weekly | `ls -la ~/backups/mongodb/` |
| Check Docker logs | Weekly | `docker logs <container> --tail 50` |
| Update Docker images | Monthly | `docker-compose pull && docker-compose up -d` |
| Rotate API keys | Every 3 months | Regenerate all keys in .env files |
| Check AWS credit balance | Monthly | AWS Billing Console |
| Review Datadog metrics | Weekly | Datadog Dashboard |

---

## Troubleshooting

**OpenClaw cannot connect to MongoDB:**
```bash
# From AWS 2, test connectivity:
curl -v telnet://<BRAIN_IP>:27017
# Check firewall on AWS 1:
sudo iptables -L -n
```

**Browserless connection fails:**
```bash
# From AWS 2, test connectivity:
curl "http://<SCOUT_IP>:3000/json/version?token=<TOKEN>"
# Check firewall on AWS 3:
sudo iptables -L -n
```

**Container keeps restarting:**
```bash
docker logs <container_name> --tail 100
docker inspect <container_name> | grep -A5 "State"
```

**Out of memory:**
```bash
# Check current memory usage:
docker stats --no-stream
free -h
```
