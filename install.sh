#!/usr/bin/env bash
# GitLab self-host installer by SoftsWeb: one command, one question (the address of your GitLab).
# Usage:   sudo ./install.sh                 (asks for the address)
#          sudo ./install.sh git.example.com (no question)
#          ./install.sh --dry-run git.example.com   (only writes the files into ./out, installs nothing)
set -euo pipefail

DRY=0
DOMAIN=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) DOMAIN="$a" ;;
  esac
done

BASE="${GITLAB_DIR:-/opt/gitlab}"
SSH_PORT="${GITLAB_SSH_PORT:-2424}"
VERSION="${GITLAB_VERSION:-latest}"   # pin a version for production, for example GITLAB_VERSION=18.5.1-ce.0
[ "$DRY" = 1 ] && BASE="./out"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

if [ "$DRY" = 0 ] && [ "$(id -u)" -ne 0 ]; then die "Run it as root: sudo ./install.sh"; fi

# ---- the only question -------------------------------------------------------------
if [ -z "$DOMAIN" ]; then
  read -r -p "Address for your GitLab (example: git.example.com): " DOMAIN
fi
DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%%/*}"
echo "$DOMAIN" | grep -Eq '^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$' || die "That does not look like a domain name: '$DOMAIN'"

say "Installing GitLab on https://$DOMAIN"

# ---- checks -------------------------------------------------------------------------
if [ "$DRY" = 0 ]; then
  . /etc/os-release 2>/dev/null || true
  case "${ID:-}${ID_LIKE:-}" in *debian*|*ubuntu*) : ;; *) warn "Tested on Ubuntu and Debian only (found: ${PRETTY_NAME:-unknown})." ;; esac
  MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  [ "$MEM_MB" -ge 7000 ] || warn "This server has ${MEM_MB} MB of memory. GitLab recommends at least 8 GB."
  for p in 80 443 "$SSH_PORT"; do
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$p\$"; then die "Port $p is already in use on this server. Free it and run the script again."; fi
  done
  MYIP=$(curl -4fsS --max-time 8 https://api.ipify.org || true)
  DNSIP=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}' || true)
  if [ -n "$MYIP" ] && [ "$DNSIP" != "$MYIP" ]; then
    warn "$DOMAIN does not point to this server yet (DNS says '${DNSIP:-nothing}', this server is '$MYIP')."
    warn "Create an A record for $DOMAIN that points to this server, otherwise the free certificate cannot be issued."
    read -r -p "Continue anyway? [y/N] " yn; [ "${yn:-n}" = y ] || exit 1
  fi
fi

# ---- docker -------------------------------------------------------------------------
if [ "$DRY" = 1 ]; then
  say "(dry run) Docker would be installed here if it is missing"
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  say "Docker is already installed"
else
  say "Installing Docker with the official script"
  curl -fsSL https://get.docker.com | sh
fi

# ---- files --------------------------------------------------------------------------
mkdir -p "$BASE"
cat > "$BASE/docker-compose.yml" <<YAML
services:
  gitlab:
    image: gitlab/gitlab-ce:${VERSION}
    container_name: gitlab
    restart: unless-stopped
    hostname: ${DOMAIN}
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://${DOMAIN}'
        gitlab_rails['gitlab_shell_ssh_port'] = ${SSH_PORT}
    ports:
      - "80:80"
      - "443:443"
      - "${SSH_PORT}:22"
    volumes:
      - ./config:/etc/gitlab
      - ./logs:/var/log/gitlab
      - ./data:/var/opt/gitlab
    shm_size: "256m"
YAML
say "Wrote $BASE/docker-compose.yml"

if [ "$DRY" = 1 ]; then
  say "(dry run) Done. Nothing was installed. Run it without --dry-run to install."
  exit 0
fi

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  say "Opening ports 80, 443 and $SSH_PORT in the firewall"
  ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; ufw allow "$SSH_PORT"/tcp >/dev/null
fi

# ---- start --------------------------------------------------------------------------
say "Starting GitLab (the first start takes a few minutes)"
( cd "$BASE" && docker compose up -d )

say "Waiting until GitLab answers"
for i in $(seq 1 180); do
  code=$(curl -ks -o /dev/null -m 8 -w '%{http_code}' "https://$DOMAIN/users/sign_in" || true)
  if [ "$code" = "200" ]; then READY=1; break; fi
  printf '.'; sleep 10
done
echo
[ "${READY:-0}" = 1 ] || die "GitLab did not answer after 30 minutes. Check the logs with: docker logs gitlab"

say "GitLab is ready: https://$DOMAIN"
echo
echo "  Sign in as:   root"
echo "  Password:     docker exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password"
echo "                (GitLab deletes that file 24 hours after the first start, so save it and change it now)"
echo "  Git over SSH: port $SSH_PORT  (your server's own SSH is not touched)"
