#!/usr/bin/env bash
# Official Nous Research Hermes Agent CLI, noninteractive stable channel.
# Installs into the actual interactive desktop user's home, not root's home.
set -Eeuo pipefail
if [ "$WFS_REMOTE" = rdp ] || [ "$WFS_REMOTE" = both ]; then
  account="$WFS_RDP_USERNAME"
else
  account=abc
fi
docker exec -u 0 wfs-linux-webtop id "$account" >/dev/null ||
  { echo "Hermes target Linux account $account not found" >&2; exit 1; }
# Prerequisites for official script. Do not install npm separately on
# NodeSource Ubuntu/Debian (it conflicts with the preinstalled Node 22).
case "$WFS_DISTRO" in
  debian|ubuntu)
    docker exec -u 0 wfs-linux-webtop /bin/sh -c \
      'DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl git bash python3 libatomic1' ;;
  fedora)
    docker exec -u 0 wfs-linux-webtop dnf install -y ca-certificates curl git bash python3 libatomic ;;
  arch)
    docker exec -u 0 wfs-linux-webtop pacman -Sy --needed --noconfirm ca-certificates curl git bash python ;;
  alpine)
    docker exec -u 0 wfs-linux-webtop apk add --no-cache ca-certificates curl git bash python3 ;;
esac
home=$(docker exec -u 0 wfs-linux-webtop getent passwd "$account" | cut -d: -f6)
[ -n "$home" ] || { echo "Hermes account home missing" >&2; exit 1; }
echo "[WFS Hermes] Installing official stable CLI into Linux account $account (no provider login)."
# Download the official installer first; execute deliberately, never via a
# blind curl pipe. The upstream supports --non-interactive and skip flags.
docker exec -u 0 wfs-linux-webtop curl -fsSL \
  --connect-timeout 15 --max-time 40 \
  https://hermes-agent.nousresearch.com/install.sh -o /tmp/wfs-hermes-install.sh
timeout 550 docker exec -i -u "$account" \
  -e "HOME=$home" -e "HERMES_HOME=$home/.hermes" \
  wfs-linux-webtop bash -s <<'IN_CONTAINER'
set -Eeuo pipefail
bash /tmp/wfs-hermes-install.sh --channel stable --non-interactive \
  --skip-browser --skip-computer-use
test -x "$HOME/.local/bin/hermes"
"$HOME/.local/bin/hermes" --help >/dev/null
echo "[WFS Hermes] PASS: Hermes CLI installed and help verified."
IN_CONTAINER
echo "[WFS Hermes] Hermes is ready for subsequent provider login in the $account terminal."
