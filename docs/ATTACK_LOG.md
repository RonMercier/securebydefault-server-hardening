# Attack Log — Real Observations Post-Launch

This documents actual attack patterns observed on a fresh Ubuntu 24 cloud
server within the first 24–72 hours of going live. No links published.
No traffic sent. The IP was discovered by automated scanners within hours.

> 📖 Full writeup: [My Server Was Attacked Within 24 Hours of Going Live](https://securebydefault.io/blog/server-attacked-24-hours-live/)

---

## Timeline

**T+0h** — Server deployed, DNS configured, SSL issued. No published links.

**T+24h** — First review of Nginx error logs. Multiple IPs already probing.

**T+72h** — Pattern analysis complete. All probes blocked. Zero successful access.

---

## Probe Categories Observed

### Category 1 — Cloud Credential Hunting (Most Common)

These were the most frequent probes. Automated bots systematically
checking every common location where cloud credentials might be exposed.

```
GET /.aws/credentials
GET /.aws/config
GET /api/.env
GET /app/.env
GET /backend/.env
GET /.env
GET /.env.local
GET /.env.production
GET /.env.development
GET /secrets.json
GET /serviceAccountKey.json
GET /credentials.json
GET /config.json
GET /docker-compose.yml
```

**Why it matters:** A misconfigured server leaving any of these files
web-accessible would hand an attacker full cloud credentials. AWS access
keys found this way have been used to rack up tens of thousands in cloud
bills within hours.

**How blocked:** Nginx `location` blocks returning 404 before any
application code is reached.

---

### Category 2 — WordPress / CMS Exploits

Even without WordPress installed at the domain root, bots probe for it.

```
GET /wp-login.php
GET /wp-config.php
GET /wp-admin/
GET /wp-includes/
GET /xmlrpc.php
GET /?author=1
```

**Why it matters:** WordPress xmlrpc.php is a classic brute-force
amplification vector. A single request can attempt hundreds of password
combinations. Even if you're not running WordPress, these requests waste
server resources.

**How blocked:** Explicit `location` deny blocks in Nginx.

---

### Category 3 — Admin Panel Discovery

```
GET /admin
GET /admin/login
GET /phpmyadmin
GET /phpmyadmin/
GET /pma/
GET /manager/html        (Tomcat manager)
GET /console/            (JBoss/WildFly)
GET /actuator/           (Spring Boot)
GET /solr/admin/
```

**How blocked:** Regex location deny block, returns 404.

---

### Category 4 — Service Fingerprinting

Bots trying to identify what's running before tailoring their attack.

```
GET /server-status       (Apache mod_status)
GET /nginx_status
GET /info.php
GET /phpinfo.php
GET /_phpinfo
GET /test.php
```

**How blocked:** Combination of `server_tokens off` (hides Nginx version
in headers) and explicit deny blocks.

---

### Category 5 — Backup and Source File Hunting

```
GET /backup.sql
GET /db.sql
GET /database.sql
GET /dump.sql
GET /.git/config
GET /.git/HEAD
GET /.svn/entries
GET /www.zip
GET /backup.zip
GET /site.tar.gz
```

**Why it matters:** Exposed `.git` directories are a real and common
problem. They can leak the entire application source code including
any secrets hardcoded in config files (which happens more than it should).

**How blocked:** Dotfile deny block (`location ~ /\.`) catches `.git`
and similar. File extension deny blocks catch backup archives.

---

### Category 6 — Miscellaneous Probes

```
GET /robots.txt          (legitimate + scrapers)
GET /favicon.ico         (browsers + scanners)
GET /.well-known/security.txt  (security researchers)
GET /sitemap.xml
GET /crossdomain.xml
GET /clientaccesspolicy.xml
```

**Notes:** `robots.txt` and `favicon.ico` requests from scanners are
expected and harmless. `security.txt` is a legitimate RFC 9116 request
from security researchers — consider adding one.

---

## Source Patterns

- Multiple distinct IPs (distributed botnet, not a single attacker)
- Several known Tor exit nodes
- Cloud provider IP ranges (compromised cloud workloads doing the scanning)
- Geographic distribution across multiple continents

---

## Key Takeaway

Every probe in this log was fully blocked by the hardening configs in
this repository. None reached application code. None reached the database.
The hardening was in place *before* the attacks arrived.

That's the lesson: configure the locks before you put the server online,
not after you notice someone tried the door.

---

*Last updated: May 2026 · New patterns welcome via GitHub Issues*
