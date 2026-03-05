#!/bin/bash
set -euo pipefail

echo "=== Tailscale Firewall Setup for AWS 1 (Brain) ==="
echo "This script configures iptables to only allow traffic from Tailscale network."
echo ""

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root (sudo)."
  exit 1
fi

TAILSCALE_INTERFACE="tailscale0"

if ! ip link show "$TAILSCALE_INTERFACE" > /dev/null 2>&1; then
  echo "ERROR: Tailscale interface not found. Install and connect Tailscale first."
  exit 1
fi

echo "[1/5] Flushing existing rules..."
iptables -F INPUT
iptables -F OUTPUT

echo "[2/5] Setting default policies..."
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

echo "[3/5] Allowing loopback and established connections..."
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

echo "[4/5] Allowing SSH (port 22) from any source for emergency access..."
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

echo "[5/5] Allowing MongoDB (27017) and LiteLLM (4000) ONLY from Tailscale..."
iptables -A INPUT -i "$TAILSCALE_INTERFACE" -p tcp --dport 27017 -j ACCEPT
iptables -A INPUT -i "$TAILSCALE_INTERFACE" -p tcp --dport 4000 -j ACCEPT

echo ""
echo "Saving rules..."
if command -v netfilter-persistent > /dev/null 2>&1; then
  netfilter-persistent save
elif command -v iptables-save > /dev/null 2>&1; then
  iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
fi

echo ""
echo "=== Firewall configured ==="
echo "MongoDB (27017) and LiteLLM (4000) are now ONLY accessible via Tailscale."
echo "Public internet CANNOT reach these ports."
