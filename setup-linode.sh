#!/usr/bin/env bash
# Setup script for Stravolt on a fresh Linode (Ubuntu 22.04 / 24.04)
# Run as root: bash setup-linode.sh
set -euo pipefail

APP_DIR="/root/stravolt"
RUBY_VERSION="3.4.8"
RBENV_ROOT="/root/.rbenv"

green() { echo -e "\033[32m$*\033[0m"; }
step()  { echo; green "==> $*"; }

# ── 1. System packages ────────────────────────────────────────────────────────
step "Installing system packages"
apt-get update -qq
apt-get install -y --no-install-recommends \
  build-essential \
  curl \
  git \
  libsqlite3-dev \
  libssl-dev \
  libvips-dev \
  libyaml-dev \
  libffi-dev \
  libreadline-dev \
  zlib1g-dev \
  pkg-config \
  nginx

# ── 2. rbenv + Ruby ───────────────────────────────────────────────────────────
step "Installing rbenv and Ruby $RUBY_VERSION"

if [ ! -d "$RBENV_ROOT" ]; then
  git clone https://github.com/rbenv/rbenv.git "$RBENV_ROOT"
  git clone https://github.com/rbenv/ruby-build.git "$RBENV_ROOT/plugins/ruby-build"
fi

PROFILE="/root/.bashrc"
grep -qxF 'export PATH="$HOME/.rbenv/bin:$PATH"' "$PROFILE" || \
  echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> "$PROFILE"
grep -qxF 'eval "$(rbenv init -)"' "$PROFILE" || \
  echo 'eval "$(rbenv init -)"' >> "$PROFILE"

export PATH="$RBENV_ROOT/bin:$PATH"
eval "$($RBENV_ROOT/bin/rbenv init -)"

if ! rbenv versions --bare | grep -q "^${RUBY_VERSION}$"; then
  step "Compiling Ruby $RUBY_VERSION (this takes a few minutes)"
  rbenv install "$RUBY_VERSION"
fi

rbenv global "$RUBY_VERSION"

# ── 3. Bundler ────────────────────────────────────────────────────────────────
step "Installing Bundler"
"$RBENV_ROOT/shims/gem" install bundler --no-document

# ── 4. Systemd service ────────────────────────────────────────────────────────
step "Installing systemd service"
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
ExecStart=$RBENV_ROOT/shims/bundle exec thrust $RBENV_ROOT/shims/rails server -p 3000 -b 127.0.0.1
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

# ── 5. Bundle install ─────────────────────────────────────────────────────────
step "Installing gems"
export BUNDLE_WITHOUT="development:test"
"$RBENV_ROOT/shims/bundle" install

# ── 6. Precompile assets ──────────────────────────────────────────────────────
step "Precompiling assets"
RAILS_ENV=production "$RBENV_ROOT/shims/bundle" exec rails assets:precompile

# ── 7. Database migrate ───────────────────────────────────────────────────────
step "Running database migrations"
RAILS_ENV=production "$RBENV_ROOT/shims/bundle" exec rails db:migrate

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
