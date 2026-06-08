#!/usr/bin/env bash
# =============================================================================
# Chatwoot + Telegram Personal Account — one-shot deploy
# =============================================================================
# Usage:
#   bash deploy.sh              — first-time install (interactive)
#   bash deploy.sh --update     — pull code & restart
#   bash deploy.sh --reset-db   — wipe and recreate database (danger!)
#
# Requires: Ubuntu 20.04 / 22.04 / 24.04  (x86_64 or arm64)
# =============================================================================

set -euo pipefail

# ── colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}✓${NC}  $*"; }
info()    { echo -e "${BLUE}→${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
step()    { echo; echo -e "${BOLD}${BLUE}── $* ──${NC}"; }
die()     { echo -e "${RED}✗ ERROR:${NC} $*" >&2; exit 1; }
ask()     { echo -ne "${YELLOW}?${NC}  $1 "; }

# ── defaults ──────────────────────────────────────────────────────────────────
MODE="install"
COMPOSE_FILE="$(cd "$(dirname "$0")" && pwd)/docker-compose.production.yaml"
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.env"
APP_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── arg parsing ───────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --update)   MODE="update" ;;
    --reset-db) MODE="reset-db" ;;
    --help|-h)
      echo "Usage: bash deploy.sh [--update | --reset-db]"
      exit 0 ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

# ── sanity checks ─────────────────────────────────────────────────────────────
[[ "$(uname -s)" == "Linux" ]] || die "This script requires Linux."
[[ $EUID -ne 0 ]] && SUDO="sudo" || SUDO=""

echo
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Chatwoot + Telegram Personal Account — Deploy       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo

# ── step 1: docker ────────────────────────────────────────────────────────────
step "1/6  Docker"

if ! command -v docker &>/dev/null; then
  info "Docker not found — installing..."
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq ca-certificates curl gnupg lsb-release
  $SUDO install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  $SUDO systemctl enable --now docker
  # Allow current user to run docker without sudo
  $SUDO usermod -aG docker "$USER" 2>/dev/null || true
  log "Docker installed"
else
  log "Docker $(docker --version | awk '{print $3}' | tr -d ',')"
fi

# Prefer "docker compose" (plugin) over "docker-compose" (legacy)
if docker compose version &>/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose &>/dev/null; then
  DC="docker-compose"
else
  die "docker compose plugin not found. Run: apt-get install docker-compose-plugin"
fi
log "Using: $DC"

# ── step 2: .env ──────────────────────────────────────────────────────────────
step "2/6  Environment"

generate_secret() { openssl rand -hex "$1"; }

if [[ "$MODE" == "install" ]] && [[ ! -f "$ENV_FILE" ]]; then
  info "Creating .env (you can edit it later)"

  ask "Domain or IP (e.g. chatwoot.example.com) [localhost]:"
  read -r FRONTEND_HOST; FRONTEND_HOST="${FRONTEND_HOST:-localhost}"

  ask "Use HTTPS? (y/N) [N]:"
  read -r USE_SSL; USE_SSL="${USE_SSL:-N}"
  [[ "$USE_SSL" =~ ^[Yy]$ ]] && PROTOCOL="https" || PROTOCOL="http"

  FRONTEND_URL="${PROTOCOL}://${FRONTEND_HOST}"
  DB_PASS="$(generate_secret 16)"
  REDIS_PASS="$(generate_secret 16)"
  SECRET_KEY="$(generate_secret 64)"

  # ActiveRecord encryption keys
  PK="$(generate_secret 32)"
  DK="$(generate_secret 32)"
  SALT="$(generate_secret 32)"

  cat > "$ENV_FILE" <<EOF
# ── Chatwoot ──────────────────────────────────────────────────────────────────
SECRET_KEY_BASE=${SECRET_KEY}
FRONTEND_URL=${FRONTEND_URL}
FORCE_SSL=false
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_MAX_THREADS=5
ENABLE_ACCOUNT_SIGNUP=false
INSTALLATION_ENV=docker

# ── ActiveRecord Encryption (required for MFA / 2FA) ─────────────────────────
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${PK}
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${DK}
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${SALT}

# ── Database ──────────────────────────────────────────────────────────────────
POSTGRES_HOST=postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=${DB_PASS}
POSTGRES_DATABASE=chatwoot

# ── Redis ─────────────────────────────────────────────────────────────────────
REDIS_URL=redis://:${REDIS_PASS}@redis:6379
REDIS_PASSWORD=${REDIS_PASS}

# ── Storage ───────────────────────────────────────────────────────────────────
ACTIVE_STORAGE_SERVICE=local

# ── TDLib (Telegram Personal Account channel) ────────────────────────────────
TDLIB_LIB_PATH=/usr/lib/libtdjson.so
EOF

  log ".env created → ${ENV_FILE}"
  info "Review/edit it before continuing if needed."
else
  [[ -f "$ENV_FILE" ]] || die ".env not found at $ENV_FILE. Run without --update first."
  log ".env exists — skipping regeneration"
fi

# Load env for this script
set -a; source "$ENV_FILE"; set +a

# ── step 3: build image ───────────────────────────────────────────────────────
step "3/6  Docker image (includes TDLib)"

cd "$APP_DIR"

if [[ "$MODE" == "update" ]]; then
  info "Pulling latest code..."
  git fetch origin
  git pull --rebase origin HEAD 2>/dev/null || git pull origin HEAD
fi

info "Building image... (first run compiles assets, ~5-10 min)"
$DC -f "$COMPOSE_FILE" build --parallel
log "Image built"

# ── step 4: start services ────────────────────────────────────────────────────
step "4/6  Services"

info "Starting postgres & redis first..."
$DC -f "$COMPOSE_FILE" up -d postgres redis
info "Waiting for postgres to be ready..."
for i in $(seq 1 30); do
  $DC -f "$COMPOSE_FILE" exec -T postgres \
    pg_isready -U postgres -q 2>/dev/null && break || true
  sleep 2
  [[ $i -eq 30 ]] && die "Postgres did not become ready in time."
done
log "Postgres ready"

if [[ "$MODE" == "reset-db" ]]; then
  warn "Resetting database..."
  $DC -f "$COMPOSE_FILE" exec -T postgres \
    psql -U postgres -c "DROP DATABASE IF EXISTS chatwoot;" 2>/dev/null || true
  $DC -f "$COMPOSE_FILE" exec -T postgres \
    psql -U postgres -c "CREATE DATABASE chatwoot;" 2>/dev/null || true
  log "Database reset"
fi

info "Starting all services..."
$DC -f "$COMPOSE_FILE" up -d
log "Services started"

# ── step 5: migrations ────────────────────────────────────────────────────────
step "5/6  Database"

info "Running migrations (may take a minute on first run)..."
$DC -f "$COMPOSE_FILE" exec -T rails \
  bash -c "POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:chatwoot_prepare"
log "Database ready"

# ── step 6: status & summary ──────────────────────────────────────────────────
step "6/6  Done"

$DC -f "$COMPOSE_FILE" ps

# Load FRONTEND_URL from env for display
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"

echo
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  Chatwoot is up!                                     ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo
echo -e "  URL:     ${BOLD}${FRONTEND_URL}${NC}"
echo -e "  Compose: ${ENV_FILE%/.env}/docker-compose.production.yaml"
echo -e "  Logs:    ${DC} -f docker-compose.production.yaml logs -f"
echo
echo -e "${BOLD}Create your first admin account:${NC}"
echo -e "  ${DC} -f docker-compose.production.yaml exec rails"
echo -e "    bundle exec rails c"
echo -e "    > Account.create!(name:'My Company'); User.create!(..."
echo
echo -e "${YELLOW}Or open ${FRONTEND_URL}/auth/sign_up in your browser (if signup is enabled).${NC}"
echo
echo -e "${BOLD}Useful commands:${NC}"
echo -e "  Restart:  ${DC} -f docker-compose.production.yaml restart"
echo -e "  Logs:     ${DC} -f docker-compose.production.yaml logs -f rails"
echo -e "  Update:   bash deploy.sh --update"
echo -e "  Stop:     ${DC} -f docker-compose.production.yaml down"
echo
echo -e "${BOLD}Telegram Personal Account setup:${NC}"
echo -e "  1. Get API ID & API Hash at ${BLUE}https://my.telegram.org${NC}"
echo -e "  2. In Chatwoot → Settings → Inboxes → Add Inbox → ${BOLD}Telegram Account${NC}"
echo -e "  3. Enter your API ID, API Hash, and phone number"
echo -e "  4. Enter the OTP code sent to your Telegram app"
echo -e "  5. Done — personal account connected!"
echo
