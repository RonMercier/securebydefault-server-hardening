# Pre-Launch Hardening Checklist

Run through this before making your server publicly accessible.
Everything in this list maps to configs in this repository.

---

## Firewall

- [ ] UFW installed and enabled (`ufw status`)
- [ ] Default incoming policy is **deny** (`ufw default deny incoming`)
- [ ] Default outgoing policy is **allow** (`ufw default allow outgoing`)
- [ ] Only required ports open: 22 (SSH), 80 (HTTP), 443 (HTTPS)
- [ ] No unexpected ports open (`ss -tlnp`)

## SSH

- [ ] SSH key pair generated and authorized key installed
- [ ] SSH login confirmed working with key before next step
- [ ] `PasswordAuthentication no` in `/etc/ssh/sshd_config`
- [ ] `PermitRootLogin no` in `/etc/ssh/sshd_config`
- [ ] `MaxAuthTries 3` in `/etc/ssh/sshd_config`
- [ ] SSHD restarted after config change (`systemctl restart sshd`)
- [ ] SSH key login confirmed still works after config change

## Nginx

- [ ] `server_tokens off` in server block
- [ ] X-Frame-Options header set (`SAMEORIGIN`)
- [ ] X-Content-Type-Options header set (`nosniff`)
- [ ] X-XSS-Protection header set
- [ ] Referrer-Policy header set
- [ ] HSTS header set (after SSL is confirmed working)
- [ ] Sensitive path blocks in place (`.env`, `.aws`, `.git`, etc.)
- [ ] xmlrpc.php blocked if running WordPress
- [ ] HTTP → HTTPS redirect in place
- [ ] Config syntax valid (`nginx -t`)
- [ ] Verify with securityheaders.com after DNS is live

## SSL/TLS

- [ ] Let's Encrypt certificate issued via Certbot
- [ ] Auto-renewal configured and tested (`certbot renew --dry-run`)
- [ ] HTTPS confirmed working in browser
- [ ] HTTP correctly redirects to HTTPS

## Fail2Ban

- [ ] Fail2Ban installed and running (`systemctl status fail2ban`)
- [ ] SSH jail active (`fail2ban-client status sshd`)
- [ ] Nginx jails configured (apply `jail.local` from this repo)
- [ ] Ban time tuned (default 10min is too short — use 1hr minimum)

## System

- [ ] All packages updated (`apt update && apt upgrade`)
- [ ] Unattended upgrades enabled (`systemctl status unattended-upgrades`)
- [ ] Kernel hardening sysctl params applied (`/etc/sysctl.d/99-hardening.conf`)
- [ ] No unnecessary services running (`systemctl list-units --type=service --state=running`)

## Verification

- [ ] `scripts/audit.sh` run — no FAIL items
- [ ] Try accessing server by raw IP (not domain) — confirm no unexpected response
- [ ] Try accessing `yourdomain.com/.env` — confirm 404 response
- [ ] Try accessing `yourdomain.com/.aws/credentials` — confirm 404 response
- [ ] Try accessing `yourdomain.com/wp-login.php` — confirm 404 response
- [ ] Check open ports from outside: `nmap -sV yourdomain.com`

---

## Post-Launch (First Week)

- [ ] Check Nginx error logs for probe patterns (`tail -100 /var/log/nginx/error.log`)
- [ ] Check Fail2Ban status for triggered jails (`fail2ban-client status`)
- [ ] Check auth log for failed SSH attempts (`grep "Failed" /var/log/auth.log | tail -20`)

---

*This checklist is maintained alongside the rest of the hardening repo.*
*Report missing items via GitHub Issues.*
