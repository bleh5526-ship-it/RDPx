#!/usr/bin/env bash
# CI-only actual xrdp/Xorg/Xfce graphical login verification.
# Uses dummy credentials from the smoke test. Does NOT print passwords.
set -Eeuo pipefail
[ "$WFS_REMOTE" = both ] || { echo "xrdp GUI smoke requires both mode" >&2; exit 1; }
secret="$RUNNER_TEMP/wfs-linux/rdp-password"
[ -s "$secret" ] || { echo "Missing CI password file" >&2; exit 1; }
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends freerdp3-x11 xvfb
if command -v xfreerdp3 >/dev/null; then
  client=xfreerdp3
elif command -v xfreerdp >/dev/null; then
  client=xfreerdp
else
  echo "FreeRDP X11 client not installed" >&2
  exit 1
fi
test_user="$WFS_RDP_USERNAME"
echo "[WFS RDP Smoke] Graphical client will authenticate to xrdp as $test_user (password masked)."
log="$RUNNER_TEMP/wfs-rdp-gui-client.log"
(
  set +e
  # Only CI dummy credentials are used here; no user secrets.
  # FreeRDP 3 in Ubuntu 24.04 does not accept /from-stdin:force on
  # all versions; pass the generated *test* password to the CLI instead.
  dummy_password="$(cat "$secret")"
  timeout 80 xvfb-run -a -s '-screen 0 1024x768x24' \
    "$client" /v:127.0.0.1:13389 /u:"$test_user" /p:"$dummy_password" \
    /cert:ignore /sec:tls /size:1024x768 \
    /log-level:WARN > "$log" 2>&1
  unset dummy_password
  exit 0
) &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT
ready=no
for attempt in $(seq 1 35); do
  if docker exec -u 0 wfs-linux-webtop /bin/sh -c \
      "pgrep -u '$test_user' -x xfce4-session >/dev/null && pgrep -u '$test_user' -x xfwm4 >/dev/null && pgrep -u '$test_user' -x xfdesktop >/dev/null"; then
    ready=yes
    break
  fi
  if ! kill -0 "$pid" 2>/dev/null; then break; fi
  sleep 2
done
if [ "$ready" != yes ]; then
  echo "::error::Actual GUI login did not launch xfce4-session + xfwm4 + xfdesktop for $test_user."
  echo "[WFS RDP Smoke] FreeRDP client diagnostics (no passwords):"
  tail -50 "$log" || true
  echo "[WFS RDP Smoke] xrdp-sesman:"
  docker exec -u 0 wfs-linux-webtop /bin/sh -c 'tail -65 /var/log/xrdp-sesman.log' || true
  echo "[WFS RDP Smoke] user startup:"
  docker exec -u 0 wfs-linux-webtop /bin/sh -c 'tail -60 "$1/.wfs-xrdp-session.log" 2>/dev/null || true' -- "$(docker exec -u 0 wfs-linux-webtop getent passwd "$test_user" | cut -d: -f6)" || true
  exit 1
fi
echo "PASS: FreeRDP graphical session connected as $test_user and spawned xfce4-session, xfwm4, and xfdesktop."
echo "PASS: verified Xorg/Xfce window manager and desktop processes — TCP/PAM alone are no longer accepted."
