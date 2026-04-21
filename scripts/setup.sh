#!/usr/bin/env bash
# =============================================================================
#  setup.sh – Bootstrap script for atithi.social on Ubuntu 24.04
#
#  Run as root on a fresh DigitalOcean droplet:
#    curl -fsSL https://raw.githubusercontent.com/akamartin/atithi-social/main/scripts/setup.sh | sudo bash
#  OR after cloning the repo:
#    sudo bash /path/to/atithi-social/scripts/setup.sh
#
#  What this script does:
#    1. Hardens the system (updates, UFW firewall)
#    2. Creates a non-root deploy user with Docker access
#    3. Installs Docker Engine + Docker Compose plugin
#    4. Installs Nginx and Certbot
#    5. Sets up the application directory and clones the repo
#    6. Copies the Nginx site config and enables it
#    7. Obtains a Let's Encrypt SSL certificate
#    8. Prints the next steps for the operator
# =============================================================================
set -euo pipefail
 
# ─── Configuration ────────────────────────────────────────────────────────────
DOMAIN="atithi.social"
ADMIN_EMAIL="admin@atithi.social"
DEPLOY_USER="deploy"
APP_DIR="/opt/atithi-social"
REPO_URL="https://github.com/akamartin/atithi-social.git"
REPO_BRANCH="main"
 
# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLD='\033[1m'
RST='\033[0m'
 
info()    { echo -e "${GRN}[INFO]${RST}  $*"; }
warn()    { echo -e "${YLW}[WARN]${RST}  $*"; }
error()   { echo -e "${RED}[ERROR]${RST} $*" >&2; exit 1; }
section() { echo -e "\n${BLD}══════════════════════════════════════${RST}"; \
            echo -e "${BLD}  $*${RST}"; \
            echo -e "${BLD}══════════════════════════════════════${RST}"; }
 
# ─── Pre-flight checks ────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || error "This script must be run as root (use sudo)."
 
OS_ID=$(. /etc/os-release && echo "$ID")
OS_VER=$(. /etc/os-release && echo "$VERSION_ID")
[[ "$OS_ID" == "ubuntu" && "$OS_VER" == "24.04" ]] \
    || warn "Tested on Ubuntu 24.04; current OS: ${OS_ID} ${OS_VER}. Proceeding anyway."
 
section "1 / 8  System update and hardening"
 
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y -q
apt-get install -y -q \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    ufw \
    fail2ban \
    unattended-upgrades \
    git
 
# Firewall – allow SSH, HTTP, HTTPS; deny everything else
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
info "UFW firewall configured."
 
# Enable automatic security updates
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
info "Unattended security upgrades enabled."
 
section "2 / 8  Creating deploy user: ${DEPLOY_USER}"
 
if id "$DEPLOY_USER" &>/dev/null; then
    info "User '$DEPLOY_USER' already exists – skipping."
else
    useradd -m -s /bin/bash -G sudo "$DEPLOY_USER"
    # Lock password login – access via SSH key only
    passwd -l "$DEPLOY_USER"
    info "User '$DEPLOY_USER' created (password-locked; use SSH keys)."
fi
 
# Ensure SSH directory exists for the deploy user
DEPLOY_HOME=$(getent passwd "$DEPLOY_USER" | cut -d: -f6)
mkdir -p "${DEPLOY_HOME}/.ssh"
chmod 700 "${DEPLOY_HOME}/.ssh"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_HOME}/.ssh"
 
warn "Add your SSH public key to ${DEPLOY_HOME}/.ssh/authorized_keys before logging out!"
 
section "3 / 8  Installing Docker Engine"
 
if command -v docker &>/dev/null; then
    info "Docker already installed: $(docker --version)"
else
    # Official Docker install script method (Ubuntu 24.04 supported)
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
 
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
 
    apt-get update -q
    apt-get install -y -q \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
 
    systemctl enable --now docker
    info "Docker installed: $(docker --version)"
fi
 
# Grant deploy user Docker access
usermod -aG docker "$DEPLOY_USER"
info "Added '$DEPLOY_USER' to the docker group."
 
section "4 / 8  Installing Nginx and Certbot"
 
apt-get install -y -q nginx certbot python3-certbot-nginx
 
systemctl enable --now nginx
info "Nginx installed and started: $(nginx -v 2>&1)"
info "Certbot installed: $(certbot --version)"
 
# Create the ACME challenge webroot used by Certbot
mkdir -p /var/www/certbot
chown www-data:www-data /var/www/certbot
 
section "5 / 8  Setting up application directory: ${APP_DIR}"
 
mkdir -p "$APP_DIR"
chown "${DEPLOY_USER}:${DEPLOY_USER}" "$APP_DIR"
 
if [[ -d "${APP_DIR}/.git" ]]; then
    info "Repo already cloned at ${APP_DIR}. Pulling latest changes."
    sudo -u "$DEPLOY_USER" git -C "$APP_DIR" pull origin "$REPO_BRANCH"
else
    info "Cloning ${REPO_URL} (branch: ${REPO_BRANCH}) → ${APP_DIR}"
    sudo -u "$DEPLOY_USER" git clone --branch "$REPO_BRANCH" "$REPO_URL" "$APP_DIR"
fi
 
# Ensure secrets file exists (operator must fill it in before starting services)
if [[ ! -f "${APP_DIR}/.env" ]]; then
    cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
    chown "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}/.env"
    chmod 600 "${APP_DIR}/.env"
    warn ".env created from .env.example – EDIT IT BEFORE STARTING SERVICES!"
else
    info ".env already exists – skipping copy."
fi
 
section "6 / 8  Configuring Nginx"
 
NGINX_AVAILABLE="/etc/nginx/sites-available/${DOMAIN}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}"
 
cp "${APP_DIR}/nginx/${DOMAIN}.conf" "$NGINX_AVAILABLE"
 
if [[ ! -L "$NGINX_ENABLED" ]]; then
    ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"
fi
 
# Disable the default site if present
rm -f /etc/nginx/sites-enabled/default
 
nginx -t && systemctl reload nginx
info "Nginx configuration for ${DOMAIN} installed and reloaded."
 
section "7 / 8  Obtaining Let's Encrypt SSL certificate"
 
# Check if a cert already exists for this domain
if certbot certificates 2>/dev/null | grep -q "Domains:.*${DOMAIN}"; then
    info "Certificate for ${DOMAIN} already exists – skipping issuance."
else
    info "Requesting certificate for ${DOMAIN} and www.${DOMAIN}…"
    certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        --redirect \
        -d "$DOMAIN" \
        -d "www.${DOMAIN}"
    info "Certificate obtained successfully."
fi
 
# Ensure Certbot auto-renewal timer is active
systemctl enable --now certbot.timer 2>/dev/null || true
info "Certbot renewal timer enabled."
 
section "8 / 8  Setup complete"
 
echo ""
echo -e "${BLD}Next steps:${RST}"
echo ""
echo -e "  1. ${YLW}Edit secrets${RST}"
echo "     sudo -u ${DEPLOY_USER} nano ${APP_DIR}/.env"
echo "     Fill in all CHANGE_ME values (DB passwords, Redis password, SMTP, etc.)"
echo ""
echo -e "  2. ${YLW}Start services${RST}"
echo "     cd ${APP_DIR}"
echo "     sudo -u ${DEPLOY_USER} docker compose up -d"
echo ""
echo -e "  3. ${YLW}Monitor startup${RST}"
echo "     sudo -u ${DEPLOY_USER} docker compose logs -f friendica"
echo ""
echo -e "  4. ${YLW}Create admin account${RST}"
echo "     Visit https://${DOMAIN} and register with the email in FRIENDICA_ADMIN_MAIL."
echo "     That account will automatically have admin privileges."
echo ""
echo -e "  5. ${YLW}Verify federation${RST}"
echo "     Check https://${DOMAIN}/nodeinfo/2.0 – should return JSON."
echo ""
echo -e "${GRN}Server IP:${RST} $(curl -s4 ifconfig.me || hostname -I | awk '{print $1}')"
echo -e "${GRN}Domain:${RST}    https://${DOMAIN}"
echo ""