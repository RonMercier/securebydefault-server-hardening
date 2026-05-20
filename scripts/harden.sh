#!/bin/bash
# securebydefault-server-hardening — scripts/harden.sh
#
# Automated hardening script for Ubuntu 24 LTS cloud VPS.
# Run as root or with sudo.
#
# What this script does:
#   1. Updates the system
#   2. Configures UFW firewall (deny-by-default, allow 22/80/443)
#   3. Hardens SSH daemon config
#   4. Applies kernel hardening sysctl parameters
#   5. Enables unattended security updates
#   6. Installs and starts Fail2Ban
#
# What it does NOT do (configure manually — see README):
#   - Nginx config (site-specific)
#   - SSL/TLS certificates (use certbot)
#   - WordPress-specific hardening
#
# Usage:
#   chmod +x scripts/harden.sh
#   sudo ./scripts/harden.sh

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail() { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }

# ── Root check ────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    fail "Run as root: sudo ./scripts/harden.sh"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SecureByDefault — Server Hardening Script"
echo "  github.com/RonMercier/securebydefault-server-hardening"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. System update ──────────────────────────────────────────
log "Updating system packages..."
apt-get update -q && apt-get upgrade -y -q
ok "System updated"

# ── 2. Install required packages ─────────────────────────────
log "Installing required packages..."
apt-get install -y -q ufw fail2ban unattended-upgrades curl
ok "Packages installed"

# ── 3. UFW Firewall ───────────────────────────────────────────
log "Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable
ok "UFW configured: deny-by-default, allow 22/80/443"

# ── 4. SSH hardening ──────────────────────────────────────────
log "Hardening SSH..."
SSH_CONFIG="/etc/ssh/sshd_config"

# Backup original
cp "$SSH_CONFIG" "${SSH_CONFIG}.backup.$(date +%Y%m%d)"

# Apply hardened settings
# NOTE: This assumes you have SSH key auth already set up.
# If not, DO NOT disable PasswordAuthentication until keys are working.
declare -A SSH_SETTINGS=(
    ["PermitRootLogin"]="no"
    ["PasswordAuthentication"]="no"
    ["PubkeyAuthentication"]="yes"
    ["AuthorizedKeysFile"]=".ssh/authorized_keys"
    ["PermitEmptyPasswords"]="no"
    ["X11Forwarding"]="no"
    ["MaxAuthTries"]="3"
    ["LoginGraceTime"]="30"
    ["ClientAliveInterval"]="300"
    ["ClientAliveCountMax"]="2"
    ["AllowAgentForwarding"]="no"
    ["AllowTcpForwarding"]="no"
    ["Protocol"]="2"
)

for key in "${!SSH_SETTINGS[@]}"; do
    value="${SSH_SETTINGS[$key]}"
    if grep -q "^${key}" "$SSH_CONFIG"; then
        sed -i "s/^${key}.*/${key} ${value}/" "$SSH_CONFIG"
    elif grep -q "^#${key}" "$SSH_CONFIG"; then
        sed -i "s/^#${key}.*/${key} ${value}/" "$SSH_CONFIG"
    else
        echo "${key} ${value}" >> "$SSH_CONFIG"
    fi
done

systemctl restart sshd
ok "SSH hardened (root login disabled, password auth disabled)"
warn "Verify you can SSH with your key BEFORE closing this session"

# ── 5. Sysctl kernel hardening ────────────────────────────────
log "Applying kernel hardening parameters..."
SYSCTL_FILE="/etc/sysctl.d/99-hardening.conf"

cat > "$SYSCTL_FILE" << 'EOF'
# SecureByDefault — Kernel hardening parameters
# See: https://github.com/RonMercier/securebydefault-server-hardening

# ── Network ──────────────────────────────────────────────────
# Disable IP forwarding (not a router)
net.ipv4.ip_forward = 0

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Protect against SYN flood attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Disable ICMP redirect acceptance
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Enable reverse path filtering (anti-spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1

# ── Shared memory ─────────────────────────────────────────────
# Restrict shared memory access
kernel.shmmax = 268435456

# ── Core dumps ───────────────────────────────────────────────
# Disable core dumps (can leak sensitive data)
fs.suid_dumpable = 0
kernel.core_uses_pid = 1

# ── Address space randomization ──────────────────────────────
kernel.randomize_va_space = 2
EOF

sysctl -p "$SYSCTL_FILE" > /dev/null
ok "Kernel hardening parameters applied"

# ── 6. Unattended upgrades ────────────────────────────────────
log "Enabling unattended security upgrades..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "root";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

ok "Unattended security updates enabled"

# ── 7. Fail2Ban ───────────────────────────────────────────────
log "Configuring Fail2Ban..."
systemctl enable fail2ban
systemctl start fail2ban
ok "Fail2Ban enabled and started"
warn "Apply jail.local from this repo manually — see README for Nginx-specific jails"

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}  Hardening complete.${NC}"
echo ""
echo "  Next steps:"
echo "  1. Verify SSH key access before closing this session"
echo "  2. Apply nginx/securebydefault.conf (customize for your domain)"
echo "  3. Apply fail2ban/jail.local from this repo"
echo "  4. Run scripts/audit.sh to verify the baseline"
echo "  5. Check securityheaders.com after Nginx is configured"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
