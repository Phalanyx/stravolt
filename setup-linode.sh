#!/usr/bin/env bash
# Setup script for Stravolt on a fresh Linode (Ubuntu 22.04 / 24.04)
# Run as root: bash setup-linode.sh
set -euo pipefail

APP_USER="rails"
APP_DIR="/var/www/stravolt"
RUBY_VERSION="3.4.8"

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

# ── 2. App user ───────────────────────────────────────────────────────────────
step "Creating app user '$APP_USER'"
if ! id "$APP_USER" &>/dev/null; then
  useradd --system --shell /bin/bash --create-home "$APP_USER"
fi

# ── 3. rbenv + Ruby ───────────────────────────────────────────────────────────
step "Installing rbenv and Ruby $RUBY_VERSION"
RBENV_ROOT="/home/$APP_USER/.rbenv"

if [ ! -d "$RBENV_ROOT" ]; then
  sudo -u "$APP_USER" git clone https://github.com/rbenv/rbenv.git "$RBENV_ROOT"
  sudo -u "$APP_USER" git clone https://github.com/rbenv/ruby-build.git "$RBENV_ROOT/plugins/ruby-build"
fi

PROFILE="/home/$APP_USER/.bashrc"
grep -qxF 'export PATH="$HOME/.rbenv/bin:$PATH"' "$PROFILE" || \
  echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> "$PROFILE"
grep -qxF 'eval "$(rbenv init -)"' "$PROFILE" || \
  echo 'eval "$(rbenv init -)"' >> "$PROFILE"

RBENV="sudo -u $APP_USER $RBENV_ROOT/bin/rbenv"

if ! $RBENV versions --bare | grep -q "^${RUBY_VERSION}$"; then
  step "Compiling Ruby $RUBY_VERSION (this takes a few minutes)"
  sudo -u "$APP_USER" bash -c "cd ~ && $RBENV_ROOT/bin/rbenv install $RUBY_VERSION"
fi

$RBENV global "$RUBY_VERSION"

# ── 4. Bundler ────────────────────────────────────────────────────────────────
step "Installing Bundler"
sudo -u "$APP_USER" "$RBENV_ROOT/shims/gem" install bundler --no-document

# ── 5. App directory ──────────────────────────────────────────────────────────
step "Setting up app directory at $APP_DIR"
mkdir -p "$APP_DIR"
chown "$APP_USER:$APP_USER" "$APP_DIR"

# ── 6. Systemd service ────────────────────────────────────────────────────────
step "Installing systemd service"
cat > /etc/systemd/system/stravolt.service <<EOF
[Unit]
Description=Stravolt Rails App
After=network.target

[Service]
Type=simple
User=$APP_USER
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

# ── Done ──────────────────────────────────────────────────────────────────────
echo
green "✓ Done. Next steps:"
echo "  1. Copy your app to $APP_DIR and your .env file"
echo "  2. sudo -u $APP_USER $RBENV_ROOT/shims/bundle install --without development test"
echo "  3. sudo -u $APP_USER $RBENV_ROOT/shims/bundle exec rails assets:precompile"
echo "  4. sudo -u $APP_USER $RBENV_ROOT/shims/bundle exec rails db:migrate"
echo "  5. Place nginx.conf in /etc/nginx/sites-available/stravolt and symlink it"
echo "     sudo ln -s /etc/nginx/sites-available/stravolt /etc/nginx/sites-enabled/"
echo "     sudo nginx -t && sudo systemctl reload nginx"
echo "  6. sudo systemctl start stravolt"
