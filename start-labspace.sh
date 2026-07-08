#!/bin/bash
# start-labspace.sh - Launch the sbx Labspace
#
# Prerequisites (automatically checked on startup):
#
#   macOS:
#     brew install ttyd
#     brew install docker/tap/sbx
#
#   Linux:
#     sudo apt install ttyd
#     curl -fsSL https://get.docker.com | sudo REPO_ONLY=1 sh
#     sudo apt-get install docker-sbx
#     sudo usermod -aG kvm $USER && newgrp kvm
#
#   If any prerequisite is missing, this script will tell you
#   exactly what to install and exit cleanly.

set -e

TTYD_PORT=8085
COMPOSE_FILE="compose.override.yaml"

# ── Color helpers ──────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}WARN:${NC} $*"; }
error() { echo -e "${RED}ERROR:${NC} $*"; exit 1; }

# ── 1. Check ttyd ──────────────────────────────────────────────
if ! command -v ttyd &>/dev/null; then
  echo ""
  echo -e "${RED}ERROR: ttyd not found.${NC}"
  echo ""
  echo "  Install it with:"
  echo "    brew install ttyd          # macOS"
  echo "    sudo apt install ttyd      # Ubuntu/Debian"
  echo ""
  echo "  Then re-run: bash start.sh"
  exit 1
fi

# ── 2. Check sbx ───────────────────────────────────────────────
if ! command -v sbx &>/dev/null; then
  echo ""
  echo -e "${RED}ERROR: sbx not found.${NC}"
  echo ""
  echo "  Install it with:"
  echo "    brew install docker/tap/sbx          # macOS"
  echo "    sudo apt install docker-sandbox       # Ubuntu (if available)"
  echo ""
  echo "  Or check: https://docs.docker.com/go/sbx/"
  echo ""
  echo "  Then re-run: bash start.sh"
  exit 1
fi

# ── 3. Ensure sbx daemon is running ────────────────────────────
#   NOTE: `sbx daemon start` (no flags) runs in the FOREGROUND and blocks
#   until Ctrl+C. Never capture it with $(...) — that hangs the script with
#   no output when the daemon isn't already up. Use `-d` (detach) instead.
#   Also: `sbx daemon status` exits 0 whether running OR stopped, so we key
#   off the "Status: running" text, not the exit code.
daemon_running() { sbx daemon status 2>/dev/null | grep -q "Status: running"; }
if daemon_running; then
  info "sbx daemon already running"
else
  info "sbx daemon not running — starting it (detached)..."
  sbx daemon start -d &>/dev/null || true
  for _ in $(seq 1 15); do
    daemon_running && break
    sleep 1
  done
  if ! daemon_running; then
    error "sbx daemon failed to start. Run 'sbx daemon start' manually to see the error."
  fi
  info "sbx daemon started"
fi

SBX_VERSION=$(sbx version 2>/dev/null)
info "sbx version: $SBX_VERSION"

# ── 4. Set CONTENT_PATH (fixes 'empty section between colons') ──
export CONTENT_PATH="${CONTENT_PATH:-$(pwd)}"
info "CONTENT_PATH set to: $CONTENT_PATH"

# Pin the Compose project name so the instructions volume has a
# deterministic name we can seed below.
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}"
info "COMPOSE_PROJECT_NAME set to: $COMPOSE_PROJECT_NAME"

# ── 5. Validate compose.override.yaml exists ───────────────────
if [ ! -f "$COMPOSE_FILE" ]; then
  error "$COMPOSE_FILE not found. Are you running from the repo root?"
fi

# ── 6. Clear port ──────────────────────────────────────────────
info "Clearing port $TTYD_PORT..."
lsof -ti tcp:$TTYD_PORT | xargs kill -9 2>/dev/null || true
sleep 1

# ── 7. Start ttyd ──────────────────────────────────────────────
info "Starting terminal on port $TTYD_PORT..."
ttyd -p $TTYD_PORT --writable --max-clients 4 zsh &
TTYD_PID=$!
sleep 1

if ! lsof -ti tcp:$TTYD_PORT &>/dev/null; then
  error "ttyd failed to start on port $TTYD_PORT"
fi
info "ttyd PID: $TTYD_PID"

# ── 8. Start Labspace (use local compose file if present, ───────
#       otherwise fall back to OCI reference)  ──────────────────
if [ -f "docker-compose.yml" ]; then
  BASE_COMPOSE="docker-compose.yml"
elif [ -f "compose.yaml" ]; then
  BASE_COMPOSE="compose.yaml"
elif [ -f "compose.yml" ]; then
  BASE_COMPOSE="compose.yml"
else
  BASE_COMPOSE=""
fi

# ── 8a. Seed the instructions volume ───────────────────────────
#   The dev-content flow copies ./ into /project but does NOT populate
#   /labspace/instructions. Compose 'watch' (action: sync) only syncs on
#   file *changes*, not at boot, so without this the interface crash-loops
#   with: ENOENT /labspace/instructions/labspace.yaml. Pre-seed it so the
#   interface finds labspace.yaml on first start; watch handles live edits.
INSTR_VOL="${COMPOSE_PROJECT_NAME}_labspace-instructions"
if [ -d "labspace" ]; then
  info "Seeding instructions volume ($INSTR_VOL) from ./labspace..."
  docker volume create "$INSTR_VOL" >/dev/null
  docker run --rm \
    -v "$INSTR_VOL":/instructions \
    -v "$PWD/labspace":/src:ro \
    alpine sh -c 'cp -a /src/. /instructions/'
else
  warn "No ./labspace directory found — skipping instructions seed"
fi

if [ -n "$BASE_COMPOSE" ]; then
  info "Starting Labspace (local compose: $BASE_COMPOSE)..."
  docker compose \
    -f "$BASE_COMPOSE" \
    -f "$COMPOSE_FILE" \
    up &
else
  info "Starting Labspace (OCI reference)..."
  docker compose \
    -f oci://dockersamples/labspace \
    -f "$COMPOSE_FILE" \
    up &
fi
COMPOSE_PID=$!

echo ""
echo "==========================================="
echo "  Labspace ready at http://localhost:3030"
echo "  Term 1 / Term 2  →  your Mac terminal"
echo "  Run: sbx ls, sbx version, sbx run ..."
echo "==========================================="
echo ""
echo "Press Ctrl+C to stop"

# ── 9. Cleanup on exit ─────────────────────────────────────────
cleanup() {
  echo ""
  info "Stopping..."
  kill $TTYD_PID 2>/dev/null || true
  if [ -n "$BASE_COMPOSE" ]; then
    docker compose \
      -f "$BASE_COMPOSE" \
      -f "$COMPOSE_FILE" \
      down 2>/dev/null || true
  else
    docker compose \
      -f oci://dockersamples/labspace \
      -f "$COMPOSE_FILE" \
      down 2>/dev/null || true
  fi
}
trap cleanup EXIT
wait $COMPOSE_PID
