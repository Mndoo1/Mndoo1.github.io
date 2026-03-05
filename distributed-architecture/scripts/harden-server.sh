#!/bin/bash
set -euo pipefail

echo "=== Docker Security Hardening ==="
echo ""

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root (sudo)."
  exit 1
fi

echo "[1/6] Configuring Docker daemon security settings..."
mkdir -p /etc/docker

cat > /etc/docker/daemon.json << 'EOF'
{
  "icc": false,
  "live-restore": true,
  "userns-remap": "default",
  "no-new-privileges": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

echo "[2/6] Setting Docker socket permissions..."
chmod 660 /var/run/docker.sock

echo "[3/6] Disabling Docker remote API on TCP..."
if grep -q "^ExecStart.*-H tcp" /lib/systemd/system/docker.service 2>/dev/null; then
  echo "WARNING: Docker is listening on TCP. Disable this in /lib/systemd/system/docker.service"
fi

echo "[4/6] Setting up automatic security updates..."
if command -v yum > /dev/null 2>&1; then
  yum install -y yum-cron > /dev/null 2>&1
  sed -i 's/apply_updates = no/apply_updates = yes/' /etc/yum/yum-cron.conf 2>/dev/null || true
  systemctl enable yum-cron 2>/dev/null || true
  systemctl start yum-cron 2>/dev/null || true
elif command -v apt-get > /dev/null 2>&1; then
  apt-get install -y unattended-upgrades > /dev/null 2>&1
  dpkg-reconfigure -plow unattended-upgrades 2>/dev/null || true
fi

echo "[5/6] Configuring SSH hardening..."
SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONFIG" ]; then
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
  sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$SSHD_CONFIG"
  sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$SSHD_CONFIG"
  echo "SSH hardened: Password auth disabled, root login disabled, max 3 auth tries."
fi

echo "[6/6] Setting up fail2ban for SSH brute-force protection..."
if command -v yum > /dev/null 2>&1; then
  amazon-linux-extras install epel -y > /dev/null 2>&1 || true
  yum install -y fail2ban > /dev/null 2>&1
elif command -v apt-get > /dev/null 2>&1; then
  apt-get install -y fail2ban > /dev/null 2>&1
fi

if command -v fail2ban-client > /dev/null 2>&1; then
  cat > /etc/fail2ban/jail.local << 'JAIL'
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
JAIL
  systemctl enable fail2ban 2>/dev/null || true
  systemctl restart fail2ban 2>/dev/null || true
  echo "fail2ban configured: 3 failed SSH attempts = 1 hour ban."
fi

echo ""
echo "=== Security hardening complete ==="
echo "IMPORTANT: Restart Docker to apply daemon.json changes:"
echo "  sudo systemctl restart docker"
echo ""
echo "IMPORTANT: Restart SSH to apply sshd_config changes:"
echo "  sudo systemctl restart sshd"
