#!/usr/bin/env bash
# Setup script for Stravolt on a fresh Linode (Ubuntu 22.04 / 24.04)
# Run as root: bash setup-linode.sh
set -euo pipefail

APP_DIR="$(pwd)"

green() { echo -e "\033[32m$*\033[0m"; }
step()  { echo; green "==> $*"; }

# ── 1. System packages ────────────────────────────────────────────────────────
step "Installing system packages"
apt-get update -qq
apt-get install -y --no-install-recommends \
  build-essential \
  curl \
  git \
  ruby-full \
  libsqlite3-dev \
  libssl-dev \
  libvips-dev \
  libyaml-dev \
  libffi-dev \
  libreadline-dev \
  zlib1g-dev \
  pkg-config \
  nginx

# ── 2. Bundler ────────────────────────────────────────────────────────────────
step "Installing Bundler"
gem install bundler --no-document

# ── 3. Systemd service ────────────────────────────────────────────────────────
step "Installing systemd service"
BUNDLE_BIN="$(which bundle)"
RAILS_BIN="$(gem contents railties 2>/dev/null | grep 'bin/rails$' || echo "$(dirname "$BUNDLE_BIN")/rails")"

cat > /etc/systemd/system/stravolt.service <<EOF
[Unit]
Description=Stravolt Rails App
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
Environment=RAILS_ENV=production
EnvironmentFile=$APP_DIR/.env
ExecStart=$BUNDLE_BIN exec thrust $RAILS_BIN server -p 3000 -b 127.0.0.1
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=stravolt

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable stravolt

# ── 4. Bundle install ─────────────────────────────────────────────────────────
step "Installing gems"
cd "$APP_DIR"
bundle config set --local without "development test"
bundle install

# ── 5. Load env + generate SECRET_KEY_BASE if missing ────────────────────────
if [ ! -f "$APP_DIR/.env" ]; then
  echo "ERROR: $APP_DIR/.env not found. Create it before running this script." >&2
  exit 1
fi
set -a; source "$APP_DIR/.env"; set +a

if [ -z "${SECRET_KEY_BASE:-}" ]; then
  step "Generating SECRET_KEY_BASE"
  echo "SECRET_KEY_BASE=$(bundle exec rails secret)" >> "$APP_DIR/.env"
  set -a; source "$APP_DIR/.env"; set +a
fi

# ── 6. Precompile assets ──────────────────────────────────────────────────────
step "Precompiling assets"
RAILS_ENV=production bundle exec rails assets:precompile

# ── 7. Database migrate ───────────────────────────────────────────────────────
step "Running database migrations"
RAILS_ENV=production bundle exec rails db:migrate

# ── 8. Nginx ──────────────────────────────────────────────────────────────────
step "Configuring nginx"
cp "$APP_DIR/nginx.conf" /etc/nginx/sites-available/stravolt
ln -sf /etc/nginx/sites-available/stravolt /etc/nginx/sites-enabled/stravolt
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# ── 9. Start app ──────────────────────────────────────────────────────────────
step "Starting stravolt service"
systemctl start stravolt

echo
green "✓ Done."
