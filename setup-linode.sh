#!/usr/bin/env bash
# Setup script for Stravolt on a fresh Oracle Cloud / Ubuntu server
# Run as root from the app directory: bash setup-linode.sh
set -euo pipefail

APP_DIR="$(pwd)"

green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
step()   { echo; green "==> $*"; }

# ── Certificate & Key Checklist ───────────────────────────────────────────────
# Before running this script, ensure the following files are in place.
# The script will check for them in step 10 and refuse to start Docker if any
# are missing.
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │  SERVICE             │ FILE                                    │ HOW      │
# ├──────────────────────────────────────────────────────────────────────────┤
# │  tesla_http_proxy    │ vehicle-command/config/tls-cert.pem     │ generate │
# │  tesla_http_proxy    │ vehicle-command/config/tls-key.pem      │ generate │
# │  tesla_http_proxy    │ vehicle-command/config/fleet-key.pem    │ generate │
# │  Rails (.well-known) │ $APP_DIR/public-key.pem                 │ generate │
# └──────────────────────────────────────────────────────────────────────────┘
#
# NOTE: fleet-telemetry (app service) has a tls block in config.json but it
# may not be active — the cert paths in config.json reference host-level paths
# that aren't mounted into the container. Verify separately if needed.
#
# Generation commands:
#   # TLS cert + key (tesla_http_proxy self-signed):
#   cd vehicle-command
#   go run ./cmd/tls-keygen -cert config/tls-cert.pem -key config/tls-key.pem
#
#   # Fleet signing key (vehicle command authentication):
#   go run ./cmd/tesla-keygen -keyring-type file config/fleet-key.pem
#
#   # Rails public key (Tesla .well-known endpoint):
#   # Copy the public half of fleet-key.pem to $APP_DIR/public-key.pem
#   cp vehicle-command/config/fleet-key.pem $APP_DIR/public-key.pem
# ─────────────────────────────────────────────────────────────────────────────

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

# Check that ALL required certs and keys are in place before starting Docker
VEHICLE_CMD_CONFIG="$APP_DIR/vehicle-command/config"
FLEET_TELEMETRY_CERTS="/home/ubuntu/certs"
FLEET_TELEMETRY_CONFIG="/home/ubuntu/config"

missing_files=0
check_file() {
  if [ ! -f "$1" ]; then
    yellow "  [ ] Missing: $1"
    missing_files=1
  else
    green  "  [✓] Found:   $1"
  fi
}

echo
echo "Certificate / Key Checklist:"
# tesla_http_proxy (required)
check_file "$VEHICLE_CMD_CONFIG/tls-cert.pem"
check_file "$VEHICLE_CMD_CONFIG/tls-key.pem"
check_file "$VEHICLE_CMD_CONFIG/fleet-key.pem"
# Rails .well-known public key endpoint (required)
check_file "$APP_DIR/public-key.pem"
# fleet-telemetry TLS (advisory — may not be active, verify config.json paths)
if [ -d "/home/ubuntu/certs" ] && ls /home/ubuntu/certs/*.pem &>/dev/null; then
  green "  [✓] Found:   /home/ubuntu/certs/*.pem (fleet-telemetry certs)"
else
  yellow "  [?] Advisory: /home/ubuntu/certs/ has no .pem files (fleet-telemetry TLS may be inactive)"
fi

if [ "$missing_files" -eq 1 ]; then
  echo >&2
  yellow "  ⚠ Docker services NOT started — missing files above." >&2
  echo   "  See the checklist at the top of this script for generation commands." >&2
  echo   "  Once all files are in place, run: cd $APP_DIR && docker compose up -d" >&2
else
  green "  All certs present — starting Docker services."
  cd "$APP_DIR"
  docker compose up -d
fi

echo
green "✓ Done."
