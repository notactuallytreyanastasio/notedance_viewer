#!/bin/bash
set -euo pipefail

# Deploy dave (the classroom music viewer) to the Hetzner box.
#
# Same shape as marginalia's deploy: the app is a service in the blog
# stack's docker-compose (that is where Postgres and Caddy live), but its
# source is its own tree at /opt/dave. Run tests here, rsync, then drive
# compose from the blog directory.
#
# Usage:
#   ./deploy.sh          test, sync, rebuild, migrate, health check
#   ./deploy.sh -n       dry run: print the plan, change nothing
#   ./deploy.sh --no-test  deploy without running the suite (say why)
#   ./deploy.sh --host user@host

HOST="${DEPLOY_HOST:-root@deploy-host}"
APP_DIR="/opt/dave"
STACK_DIR="/opt/blog"
URL="https://dave.bobbby.online"
DRY=0
SKIP_TESTS=0

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY=1 ;;
    --no-test)    SKIP_TESTS=1 ;;
    --host)       HOST="$2"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

bold() { printf '\033[1m==>\033[0m %s\n' "$1"; }
did()  { printf '    \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$1"; }

EXCLUDES=(
  --exclude '.git' --exclude '.env' --exclude '_build' --exclude 'deps'
  --exclude 'node_modules' --exclude '.elixir_ls' --exclude 'priv/static/assets'
)

# The suite runs here, not in whatever command happened to invoke this, so a
# red suite stops the deploy and --no-test has to be typed on purpose.
if [ $SKIP_TESTS -eq 0 ] && [ $DRY -eq 0 ]; then
  bold "tests"
  if "$(dirname "$0")/bin/check" > /tmp/dave-check.log 2>&1; then
    did "$(tail -1 /tmp/dave-check.log)"
  else
    tail -30 /tmp/dave-check.log
    printf '\033[31m==> refusing to deploy over a failing suite\033[0m\n' >&2
    printf '    run ./bin/check to see it, or ./deploy.sh --no-test to override\n' >&2
    exit 1
  fi
fi

bold "dave → $HOST:$APP_DIR"

changes=$(rsync -ain --delete "${EXCLUDES[@]}" "$PWD/" "$HOST:$APP_DIR/" 2>/dev/null \
  | awk '$1 ~ /^[<>ch.*]/ && $2 != "./" {print $2}' || true)

if [ -z "$changes" ]; then
  warn "nothing changed"
else
  printf '%s\n' "$changes" | head -15 | sed 's/^/      /'
  n=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')
  [ "$n" -gt 15 ] && printf '      … and %s more\n' "$((n - 15))"
fi

migrate=0
printf '%s\n' "$changes" | grep -q '^priv/repo/migrations/' && migrate=1

if [ $DRY -eq 1 ]; then
  warn "dry run: would sync, rebuild$([ $migrate = 1 ] && echo ', migrate')"
  bold "dry run — nothing changed"
  exit 0
fi

ssh "$HOST" "mkdir -p $APP_DIR"
rsync -az --delete "${EXCLUDES[@]}" "$PWD/" "$HOST:$APP_DIR/"
did "synced"

ssh "$HOST" "cd $STACK_DIR && docker compose build dave && docker compose up -d dave" >/dev/null
did "rebuilt + restarted"

ssh "$HOST" "cd $STACK_DIR && docker compose exec -T dave /app/bin/migrate" </dev/null
did "migrated"

bold "health"
code=$(curl -s -o /dev/null -w '%{http_code}' "$URL" || echo 000)
if [ "$code" = "200" ]; then did "$URL  $code"; else warn "$URL  $code"; fi

rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
git diff --quiet 2>/dev/null || rev="$rev+dirty"
ssh "$HOST" "echo '$rev  $(date -u +%FT%TZ)' > $APP_DIR/.deployed"
bold "deploy complete"
