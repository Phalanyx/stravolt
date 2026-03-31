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
  nginx \
  libnginx-mod-stream

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
ExecStart=$BUNDLE_BIN exec rails server -p 3000 -b 127.0.0.1
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

# ── 5b. Generate Rails encryption credentials if missing ──────────────────────
if [ ! -f "$APP_DIR/config/credentials.yml.enc" ]; then
  step "Generating active_record_encryption keys"

  # Capture the YAML block printed by db:encryption:init
  ENCRYPTION_KEYS=$(RAILS_ENV=production bundle exec rails db:encryption:init)

  # Write it into credentials non-interactively via a temp editor script
  EDITOR_SCRIPT=$(mktemp /tmp/creds-editor-XXXXXX.sh)
  printf '#!/usr/bin/env bash\nprintf "%%s\n" "%s" > "$1"\n' "$ENCRYPTION_KEYS" > "$EDITOR_SCRIPT"
  chmod +x "$EDITOR_SCRIPT"
  EDITOR="$EDITOR_SCRIPT" RAILS_ENV=production bundle exec rails credentials:edit
  rm -f "$EDITOR_SCRIPT"
fi

# ── 6. Precompile assets ──────────────────────────────────────────────────────
step "Precompiling assets"
RAILS_ENV=production bundle exec rails assets:precompile

# ── 7. Database migrate ───────────────────────────────────────────────────────
step "Running database migrations"
RAILS_ENV=production bundle exec rails db:migrate

# ── 8. Nginx ──────────────────────────────────────────────────────────────────
step "Configuring nginx"
cp "$APP_DIR/nginx.conf" /etc/nginx/nginx.conf
nginx -t && systemctl reload nginx

# ── 9. Start app ──────────────────────────────────────────────────────────────
step "Starting stravolt service"
systemctl start stravolt

# ── 10. Docker services (tesla_http_proxy + fleet-telemetry) ──────────────────
step "Starting Docker services"

# Check that required TLS and fleet keys exist before starting
VEHICLE_CMD_CONFIG="$APP_DIR/vehicle-command/config"
FLEET_TELEMETRY_CERTS="/home/ubuntu/certs"

missing_files=0
for f in "$VEHICLE_CMD_CONFIG/tls-cert.pem" "$VEHICLE_CMD_CONFIG/tls-key.pem" "$VEHICLE_CMD_CONFIG/fleet-key.pem"; do
  if [ ! -f "$f" ]; then
    echo "  ✗ Missing: $f" >&2
    missing_files=1
  fi
done
for f in "$FLEET_TELEMETRY_CERTS/tls-cert.pem" "$FLEET_TELEMETRY_CERTS/tls-key.pem"; do
  if [ ! -f "$f" ]; then
    echo "  ✗ Missing: $f" >&2
    missing_files=1
  fi
done

if [ "$missing_files" -eq 1 ]; then
  echo >&2
  echo "  ⚠ Docker services NOT started. Generate and copy the required keys first:" >&2
  echo >&2
  echo "  # Generate TLS cert + key for tesla_http_proxy:" >&2
  echo "  cd \$APP_DIR/vehicle-command" >&2
  echo "  go run ./cmd/tls-keygen -cert config/tls-cert.pem -key config/tls-key.pem" >&2
  echo >&2
  echo "  # Generate fleet private key for vehicle command signing:" >&2
  echo "  go run ./cmd/tesla-keygen -keyring-type file config/fleet-key.pem" >&2
  echo >&2
  echo "  # Copy TLS certs for fleet-telemetry (app service):" >&2
  echo "  cp $VEHICLE_CMD_CONFIG/tls-cert.pem $FLEET_TELEMETRY_CERTS/tls-cert.pem" >&2
  echo "  cp $VEHICLE_CMD_CONFIG/tls-key.pem  $FLEET_TELEMETRY_CERTS/tls-key.pem" >&2
  echo >&2
  echo "  Then re-run: cd $APP_DIR && docker compose up -d" >&2
else
  cd "$APP_DIR"
  docker compose up -d
fi

echo
green "✓ Done."
