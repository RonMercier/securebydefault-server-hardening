#!/bin/bash
# securebydefault-server-hardening — scripts/audit.sh
#
# Quick security audit script — verifies the hardening baseline
# is in place and highlights anything that needs attention.
#
# Usage:
#   chmod +x scripts/audit.sh
#   sudo ./scripts/audit.sh

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; ((PASS++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
section() { echo -e "\n${CYAN}── $1 ──────────────────────────────────${NC}"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo ./scripts/audit.sh"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SecureByDefault — Security Audit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── UFW ───────────────────────────────────────────────────────
section "Firewall (UFW)"
if ufw status | grep -q "Status: active"; then
    pass "UFW is active"
else
    fail "UFW is NOT active"
fi

if ufw status | grep -q "22/tcp"; then
    pass "SSH (22) allowed"
else
    warn "SSH (22) not found in UFW rules"
fi

if ufw status | grep -q "80/tcp"; then
    pass "HTTP (80) allowed"
else
    warn "HTTP (80) not found in UFW rules"
fi

if ufw status | grep -q "443/tcp"; then
    pass "HTTPS (443) allowed"
else
    warn "HTTPS (443) not found in UFW rules"
fi

# ── SSH ───────────────────────────────────────────────────────
section "SSH Hardening"

if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
    pass "Root login disabled"
else
    fail "Root login is NOT disabled — check PermitRootLogin"
fi

if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
    pass "Password authentication disabled"
else
    warn "Password authentication may be enabled — verify PasswordAuthentication no"
fi

if grep -q "^MaxAuthTries 3" /etc/ssh/sshd_config; then
    pass "MaxAuthTries set to 3"
else
    warn "MaxAuthTries not hardened — consider setting to 3"
fi

# ── Fail2Ban ──────────────────────────────────────────────────
section "Fail2Ban"

if systemctl is-active --quiet fail2ban; then
    pass "Fail2Ban is running"
else
    fail "Fail2Ban is NOT running"
fi

if fail2ban-client status sshd &>/dev/null; then
    BANNED=$(fail2ban-client status sshd | grep "Currently banned" | awk '{print $NF}')
    pass "SSH jail active (currently banned: $BANNED IPs)"
else
    warn "SSH jail not configured — apply jail.local from this repo"
fi

# ── Nginx ─────────────────────────────────────────────────────
section "Nginx"

if systemctl is-active --quiet nginx; then
    pass "Nginx is running"
else
    warn "Nginx is not running"
fi

if nginx -t 2>&1 | grep -q "syntax is ok"; then
    pass "Nginx config syntax is valid"
else
    fail "Nginx config has syntax errors — run: sudo nginx -t"
fi

# Check security headers
if nginx -T 2>/dev/null | grep -q "X-Frame-Options"; then
    pass "X-Frame-Options header configured"
else
    warn "X-Frame-Options header not found in Nginx config"
fi

if nginx -T 2>/dev/null | grep -q "server_tokens off"; then
    pass "server_tokens off (version disclosure disabled)"
else
    warn "server_tokens not set to off — consider adding it"
fi

# ── Unattended upgrades ───────────────────────────────────────
section "Automatic Updates"

if systemctl is-active --quiet unattended-upgrades; then
    pass "Unattended upgrades service is running"
else
    warn "Unattended upgrades not running"
fi

if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
    pass "Auto-upgrade config present"
else
    warn "Auto-upgrade config not found — run harden.sh or set up manually"
fi

# ── Open ports ────────────────────────────────────────────────
section "Open Ports"

OPEN_PORTS=$(ss -tlnp | grep LISTEN | awk '{print $4}' | grep -v "127.0.0" | sort -u)
echo "  Open ports on public interfaces:"
while IFS= read -r port; do
    echo "    $port"
done <<< "$OPEN_PORTS"

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Results: ${GREEN}$PASS passed${NC}  ${YELLOW}$WARN warnings${NC}  ${RED}$FAIL failed${NC}"

if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}Address the FAIL items before exposing this server to production.${NC}"
elif [ "$WARN" -gt 0 ]; then
    echo -e "  ${YELLOW}Review the WARN items — they may indicate incomplete hardening.${NC}"
else
    echo -e "  ${GREEN}Baseline hardening checks passed.${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
