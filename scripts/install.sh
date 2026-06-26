#!/bin/bash
# ============================================================
#  cph-panel VPS Control Panel — Installer
#  Usage: bash <(curl -s https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/scripts/install.sh)
# ============================================================
set -e

PANEL_DIR="/opt/cph-panel"
SERVICE_NAME="cph-panel"
API_PORT=3001
WEB_PORT=3000
NODE_VERSION="20"
REPO_URL="https://github.com/Amir565-ux/cph-panel"
BRANCH="main"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${BLUE}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║        cph-panel  Installer           ║"
echo "  ║   VPS Hosting Control Panel Setup     ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${NC}"

# ── Root check ────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Run as root.${NC}"
  echo "  sudo bash <(curl -s <URL>)"
  exit 1
fi

# ── Detect OS ─────────────────────────────────────────────────
if [ -f /etc/debian_version ]; then
  OS="debian"
  PKG="apt-get"
elif [ -f /etc/redhat-release ]; then
  OS="rhel"
  PKG="yum"
else
  echo -e "${RED}Unsupported OS. Use Ubuntu 20+, Debian 11+, or CentOS 8+.${NC}"
  exit 1
fi

log() { echo -e "${GREEN}[✓]${NC} $1"; }
step() { echo -e "${BLUE}[→]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# ── Update packages ───────────────────────────────────────────
step "Updating system packages..."
if [ "$OS" = "debian" ]; then
  apt-get update -qq
  apt-get install -y -q curl git openssl wget ca-certificates
else
  yum install -y -q curl git openssl wget ca-certificates
fi
log "System packages updated"

# ── Install Node.js ───────────────────────────────────────────
if ! command -v node &>/dev/null || [[ $(node -v | cut -d'v' -f2 | cut -d'.' -f1) -lt 18 ]]; then
  step "Installing Node.js $NODE_VERSION..."
  if [ "$OS" = "debian" ]; then
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - &>/dev/null
  else
    curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | bash - &>/dev/null
  fi
  $PKG install -y -q nodejs
  log "Node.js $(node -v) installed"
else
  log "Node.js $(node -v) already installed"
fi

# ── Install pnpm ──────────────────────────────────────────────
if ! command -v pnpm &>/dev/null; then
  step "Installing pnpm..."
  npm install -g pnpm --quiet
  log "pnpm installed"
else
  log "pnpm already installed"
fi

# ── Install PostgreSQL ────────────────────────────────────────
if ! command -v psql &>/dev/null; then
  step "Installing PostgreSQL..."
  if [ "$OS" = "debian" ]; then
    apt-get install -y -q postgresql postgresql-contrib
  else
    yum install -y -q postgresql-server postgresql-contrib
    postgresql-setup initdb
  fi
  systemctl start postgresql
  systemctl enable postgresql
  log "PostgreSQL installed and started"
else
  log "PostgreSQL already installed"
fi

# ── Database setup ────────────────────────────────────────────
step "Setting up database..."
DB_PASSWORD=$(openssl rand -hex 20)
DB_NAME="cphpanel"
DB_USER="cphpanel"

su -c "psql -tc \"SELECT 1 FROM pg_user WHERE usename='$DB_USER'\" | grep -q 1 || psql -c \"CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';\"" postgres
su -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\" | grep -q 1 || psql -c \"CREATE DATABASE $DB_NAME OWNER $DB_USER;\"" postgres
log "Database ready"

# ── Download panel ────────────────────────────────────────────
step "Downloading cph-panel..."
if [ -d "$PANEL_DIR" ]; then
  warn "Directory $PANEL_DIR exists — pulling latest..."
  cd "$PANEL_DIR" && git pull origin "$BRANCH" &>/dev/null
else
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$PANEL_DIR" &>/dev/null
fi
log "Panel code downloaded to $PANEL_DIR"

# ── Environment ───────────────────────────────────────────────
step "Writing environment config..."
SESSION_SECRET=$(openssl rand -hex 32)

mkdir -p "$PANEL_DIR"
cat > "$PANEL_DIR/.env" << EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME
SESSION_SECRET=$SESSION_SECRET
NODE_ENV=production
EOF

mkdir -p "$PANEL_DIR/artifacts/api-server"
cat > "$PANEL_DIR/artifacts/api-server/.env" << EOF
PORT=$API_PORT
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME
SESSION_SECRET=$SESSION_SECRET
NODE_ENV=production
EOF

mkdir -p "$PANEL_DIR/artifacts/cph-panel"
cat > "$PANEL_DIR/artifacts/cph-panel/.env" << EOF
PORT=$WEB_PORT
VITE_API_BASE=/api
EOF

log "Environment config written"

# ── Install dependencies ──────────────────────────────────────
step "Installing Node.js dependencies..."
cd "$PANEL_DIR"
pnpm install --no-frozen-lockfile
log "Dependencies installed"

# ── Push database schema ──────────────────────────────────────
step "Pushing database schema..."
cd "$PANEL_DIR"
DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME" \
  pnpm --filter @workspace/db run push --accept-data-loss || \
  DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME" \
  pnpm --filter @workspace/db run push
log "Database schema applied"

# ── Build API ─────────────────────────────────────────────────
step "Building API server..."
cd "$PANEL_DIR"
PORT=$API_PORT DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME" \
  pnpm --filter @workspace/api-server run build
log "API built"

# ── Build frontend ────────────────────────────────────────────
step "Building frontend..."
cd "$PANEL_DIR"
PORT=$WEB_PORT pnpm --filter @workspace/cph-panel run build
log "Frontend built"

# ── Nginx (optional) ──────────────────────────────────────────
if ! command -v nginx &>/dev/null; then
  if [ "$OS" = "debian" ]; then
    apt-get install -y -q nginx &>/dev/null
  else
    yum install -y -q nginx &>/dev/null
  fi
fi
if command -v nginx &>/dev/null; then
  step "Configuring Nginx reverse proxy..."
  cat > /etc/nginx/sites-available/cph-panel << 'NGINX'
server {
    listen 80;
    server_name _;

    location /api/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Cookie $http_cookie;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
  ln -sf /etc/nginx/sites-available/cph-panel /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  nginx -t &>/dev/null && systemctl reload nginx
  log "Nginx configured"
fi

# ── Systemd services ──────────────────────────────────────────
step "Creating systemd services..."

cat > /etc/systemd/system/cph-panel-api.service << EOF
[Unit]
Description=cph-panel API Server
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=$PANEL_DIR/artifacts/api-server
ExecStart=/usr/bin/node --enable-source-maps ./dist/index.mjs
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=$API_PORT
EnvironmentFile=$PANEL_DIR/artifacts/api-server/.env

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/cph-panel-web.service << EOF
[Unit]
Description=cph-panel Web Frontend
After=network.target cph-panel-api.service

[Service]
Type=simple
WorkingDirectory=$PANEL_DIR/artifacts/cph-panel
ExecStart=/usr/bin/npx serve dist -p $WEB_PORT -s
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cph-panel-api
systemctl enable --now cph-panel-web
log "Services enabled and started"

# ── Done ──────────────────────────────────────────────────────
HOST_IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  cph-panel installed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Panel URL:   ${BLUE}http://$HOST_IP${NC}"
echo -e "  API URL:     ${BLUE}http://$HOST_IP/api${NC}"
echo ""
echo -e "  ${YELLOW}First user to sign up becomes the owner/admin.${NC}"
echo ""
echo "  Manage services:"
echo "    systemctl status cph-panel-api"
echo "    systemctl status cph-panel-web"
echo "    journalctl -u cph-panel-api -f"
echo ""
