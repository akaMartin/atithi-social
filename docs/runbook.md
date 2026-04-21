# Atithi Social – Operations Runbook
 
**Instance:** https://atithi.social  
**Server:** DigitalOcean Ubuntu 24.04 (IP: 161.35.113.202)  
**Stack:** Friendica (Docker) · MariaDB 11 · Redis 7 · Nginx · Let's Encrypt
 
---
 
## Table of Contents
 
1. [Prerequisites](#1-prerequisites)
2. [Initial Deployment](#2-initial-deployment)
3. [Day-to-day Operations](#3-day-to-day-operations)
4. [Updating Friendica](#4-updating-friendica)
5. [Backup and Restore](#5-backup-and-restore)
6. [Scaling](#6-scaling)
7. [Monitoring](#7-monitoring)
8. [Troubleshooting](#8-troubleshooting)
9. [Security Checklist](#9-security-checklist)
 
---
 
## 1. Prerequisites
 
| Requirement | Notes |
|---|---|
| Ubuntu 24.04 LTS | Fresh DigitalOcean droplet |
| DNS `A` record | `atithi.social` → `161.35.113.202` (must propagate before Certbot runs) |
| DNS `A` record | `www.atithi.social` → `161.35.113.202` |
| Root SSH access | Required only for `setup.sh`; day-to-day uses `deploy` user |
| Outbound port 443 | Needed for Let's Encrypt ACME challenge |
| Outbound SMTP | Only if using `SMTP` in `.env` |
 
---
 
## 2. Initial Deployment
 
### 2.1 Run the bootstrap script
 
```bash
# On the fresh droplet, as root:
curl -fsSL https://raw.githubusercontent.com/akamartin/atithi-social/main/scripts/setup.sh \
  | sudo bash
```
 
The script will:
- Update the system and enable automatic security upgrades
- Configure UFW (ports 22, 80, 443 allowed)
- Create the `deploy` user and grant Docker access
- Install Docker Engine, Nginx, and Certbot
- Clone the repo to `/opt/atithi-social`
- Copy the Nginx config and reload Nginx
- Obtain a Let's Encrypt certificate for `atithi.social` and `www.atithi.social`
 
### 2.2 Add your SSH public key
 
Before logging out as root, add the deploy user's SSH key:
 
```bash
echo "ssh-ed25519 AAAA..." >> /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
```
 
### 2.3 Configure secrets
 
```bash
sudo -u deploy nano /opt/atithi-social/.env
```
 
Fill in every `CHANGE_ME` value. Minimum required:
 
| Variable | Description |
|---|---|
| `MYSQL_ROOT_PASSWORD` | Strong random password (internal only) |
| `MYSQL_PASSWORD` | Strong random password for Friendica DB user |
| `REDIS_PASSWORD` | Strong random password |
| `FRIENDICA_ADMIN_MAIL` | Your email address (becomes the admin account) |
 
Generate strong passwords:
```bash
openssl rand -base64 32
```
 
### 2.4 Start services
 
```bash
cd /opt/atithi-social
sudo -u deploy docker compose up -d
```
 
### 2.5 Watch initialisation logs
 
```bash
docker compose logs -f friendica
```
 
First boot takes 2–5 minutes while Friendica creates the database schema. You will see:
```
friendica  | [INFO] Database successfully checked.
friendica  | [INFO] Friendica is ready.
```
 
### 2.6 Create the admin account
 
1. Visit https://atithi.social
2. Register a new account using the **exact email address** in `FRIENDICA_ADMIN_MAIL`
3. That account is automatically granted admin privileges
 
### 2.7 Verify federation
 
```bash
curl -s https://atithi.social/nodeinfo/2.0 | jq .
```
 
Should return JSON with `software.name = "friendica"`.
 
---
 
## 3. Day-to-day Operations
 
All commands assume you are logged in as the `deploy` user and are in `/opt/atithi-social`.
 
### View running containers
 
```bash
docker compose ps
```
 
### View logs (tail)
 
```bash
docker compose logs -f              # all services
docker compose logs -f friendica    # Friendica only
docker compose logs -f db           # MariaDB only
```
 
### Restart a service
 
```bash
docker compose restart friendica
```
 
### Stop all services
 
```bash
docker compose down
```
 
### Start all services
 
```bash
docker compose up -d
```
 
### Open a shell inside a container
 
```bash
docker compose exec friendica bash
docker compose exec db bash
```
 
### Run Friendica CLI commands
 
```bash
docker compose exec friendica php bin/console.php --help
docker compose exec friendica php bin/console.php worker:start
```
 
### Reload Nginx after config changes
 
```bash
sudo nginx -t && sudo systemctl reload nginx
```
 
### Check SSL certificate expiry
 
```bash
sudo certbot certificates
```
 
---
 
## 4. Updating Friendica
 
The `friendica:stable` image tracks the latest stable release. To update:
 
```bash
cd /opt/atithi-social
 
# Pull the latest image
docker compose pull friendica
 
# Recreate the container (zero-downtime if you have replicas; ~30 s otherwise)
docker compose up -d --no-deps friendica
 
# Watch for any schema migration messages
docker compose logs -f friendica
```
 
> **Note:** Friendica runs database migrations automatically on startup. Always
> read the [Friendica changelog](https://github.com/friendica/friendica/blob/stable/CHANGELOG.md)
> before upgrading in case manual steps are required.
 
### Update MariaDB or Redis
 
```bash
# Edit docker-compose.yml to bump the image tag, then:
docker compose pull db redis
docker compose up -d --no-deps db redis
```
 
### Pull latest repo changes (Nginx config, scripts, etc.)
 
```bash
git -C /opt/atithi-social pull origin main
sudo cp /opt/atithi-social/nginx/atithi.social.conf \
        /etc/nginx/sites-available/atithi.social
sudo nginx -t && sudo systemctl reload nginx
```
 
---
 
## 5. Backup and Restore
 
### 5.1 Backup
 
#### Database dump
 
```bash
BACKUP_DIR="/opt/backups/atithi-social"
mkdir -p "$BACKUP_DIR"
DATE=$(date +%Y%m%d_%H%M%S)
 
docker compose exec -T db \
    mysqldump \
    --user="${MYSQL_USER}" \
    --password="${MYSQL_PASSWORD}" \
    --single-transaction \
    --routines \
    --triggers \
    "${MYSQL_DATABASE}" \
  | gzip > "${BACKUP_DIR}/db_${DATE}.sql.gz"
```
 
#### Friendica data (uploads, config, addons)
 
The Friendica web root is stored in the `friendica_html` Docker named volume.
 
```bash
docker run --rm \
    -v atithi-social_friendica_html:/source:ro \
    -v "$BACKUP_DIR":/backup \
    alpine tar -czf /backup/friendica_html_${DATE}.tar.gz -C /source .
```
 
#### Automate with cron
 
```bash
sudo -u deploy crontab -e
```
 
Add:
```cron
# Daily backup at 02:00, keep 14 days
0 2 * * * /opt/atithi-social/scripts/backup.sh >> /var/log/atithi-backup.log 2>&1
```
 
### 5.2 Restore
 
#### Restore database
 
```bash
gunzip -c db_YYYYMMDD_HHMMSS.sql.gz \
  | docker compose exec -T db \
    mysql \
    --user="${MYSQL_USER}" \
    --password="${MYSQL_PASSWORD}" \
    "${MYSQL_DATABASE}"
```
 
#### Restore Friendica data volume
 
```bash
# Stop Friendica first
docker compose stop friendica
 
docker run --rm \
    -v atithi-social_friendica_html:/target \
    -v /path/to/backup:/backup:ro \
    alpine sh -c "cd /target && tar -xzf /backup/friendica_html_YYYYMMDD.tar.gz"
 
docker compose start friendica
```
 
---
 
## 6. Scaling
 
### Vertical scaling (recommended first step)
 
1. Take a DigitalOcean snapshot of the droplet
2. Resize the droplet in the DO console (power off → resize → power on)
3. Tune `WORKER_QUEUES` in `.env`: set to `(vCPU count) × 2`
4. Restart: `docker compose up -d friendica`
 
### Horizontal scaling considerations
 
Friendica's architecture is monolithic; horizontal scaling requires:
 
- A shared NFS or S3-compatible volume for the Friendica HTML/data directory
- A shared MariaDB instance (e.g. DO Managed Databases)
- A shared Redis instance (e.g. DO Managed Redis)
- A load balancer in front of multiple Friendica containers
 
This is an advanced topic; refer to the
[Friendica admin documentation](https://friendi.ca/resources/admin-guide/)
before attempting it.
 
---
 
## 7. Monitoring
 
### Container health at a glance
 
```bash
docker compose ps
# Healthy containers show "(healthy)" in the STATUS column
```
 
### Resource usage
 
```bash
docker stats --no-stream
```
 
### Disk usage
 
```bash
df -h /
docker system df          # Docker-specific usage
du -sh /opt/backups       # Backup directory size
```
 
### Check worker queue depth
 
```bash
docker compose exec friendica \
    php bin/console.php worker:dequeue --help
# Or inspect the DB directly:
docker compose exec db \
    mysql -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" friendica \
    -e "SELECT priority, COUNT(*) FROM workerqueue WHERE done=0 GROUP BY priority;"
```
 
### Certbot renewal dry-run
 
```bash
sudo certbot renew --dry-run
```
 
---
 
## 8. Troubleshooting
 
### Friendica shows a blank page or 502 Bad Gateway
 
1. Check if the container is running: `docker compose ps`
2. Check Friendica logs: `docker compose logs --tail=50 friendica`
3. Check Nginx error log: `sudo tail -50 /var/log/nginx/atithi.social.error.log`
4. Verify Friendica is listening: `curl -I http://127.0.0.1:8080`
 
### Database connection errors
 
```bash
docker compose logs db        # Check MariaDB logs
docker compose exec db mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES;"
```
 
If MariaDB is healthy but Friendica cannot connect, double-check `MYSQL_USER`,
`MYSQL_PASSWORD`, and `MYSQL_DATABASE` in `.env`.
 
### Redis connection errors
 
```bash
docker compose logs redis
docker compose exec redis redis-cli -a "${REDIS_PASSWORD}" ping
# Expected output: PONG
```
 
### Federation / ActivityPub not working
 
- Ensure outbound HTTPS (port 443) is not blocked: `curl -I https://mastodon.social`
- Check `FRIENDICA_URL` in `.env` – must be exactly `https://atithi.social`
- Verify NodeInfo: `curl https://atithi.social/nodeinfo/2.0`
 
### Workers not processing jobs
 
```bash
docker compose exec friendica php bin/console.php worker:start
```
 
If workers keep dying, check available memory (`free -h`) and reduce `worker_queues`
in `friendica/config/local.config.php`.
 
### Nginx returns "SSL_ERROR_RX_RECORD_TOO_LONG"
 
This usually means Nginx is returning plain HTTP on port 443. Run:
```bash
sudo certbot --nginx -d atithi.social -d www.atithi.social
sudo systemctl reload nginx
```
 
### Reset admin password
 
```bash
docker compose exec friendica \
    php bin/console.php user:password admin@atithi.social
```
 
---
 
## 9. Security Checklist
 
- [ ] `.env` has `chmod 600` and is **not** committed to git
- [ ] All `CHANGE_ME` values replaced with strong random passwords
- [ ] SSH password authentication is disabled (`PasswordAuthentication no` in `/etc/ssh/sshd_config`)
- [ ] Root login via SSH is disabled (`PermitRootLogin no`)
- [ ] UFW is active (`sudo ufw status`)
- [ ] `fail2ban` is running (`sudo systemctl status fail2ban`)
- [ ] Certbot auto-renewal is active (`sudo systemctl status certbot.timer`)
- [ ] Automatic security upgrades are enabled (`/etc/apt/apt.conf.d/20auto-upgrades`)
- [ ] Docker containers run as non-root users (Friendica image default: `www-data`)
- [ ] Friendica port `8080` is **not** publicly reachable (bound to `127.0.0.1` only)
- [ ] Regular backups are tested by attempting a restore