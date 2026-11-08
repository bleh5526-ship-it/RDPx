#!/usr/bin/env bash
# WFS Linux Remote Workspace. Browser desktops stay private to Tailscale.
set -Eeuo pipefail
name=wfs-linux-webtop
state="$RUNNER_TEMP/wfs-linux"
config="$state/config"
password_file="$state/web-password"
rdp_password_file="$state/rdp-password"
notice() { printf '[WFS Linux] %s\n' "$*"; }
die() { echo "::error::$*" >&2; exit 1; }
validate() {
  case "$WFS_DISTRO" in ubuntu|debian|fedora|arch|alpine) ;; *) die "Unsupported Linux distro: $WFS_DISTRO";; esac
  case "$WFS_DESKTOP" in xfce|kde|mate|i3) ;; *) die "Unsupported desktop: $WFS_DESKTOP";; esac
  case "$WFS_DURATION" in 1|3|6) ;; *) die "Invalid duration";; esac
  case "$WFS_TRANSPORT" in auto|tailnet_https|tailnet_tls_tcp) ;; *) die "Invalid transport";; esac
  case "$WFS_APPS" in none|developer|office|media|all) ;; *) die "Invalid app bundle";; esac
  case "$WFS_REMOTE" in rdp|novnc|both) ;; *) die "Invalid remote choice";; esac
  case "$WFS_HOSTNAME_MODE" in same_each_run|unique_each_run) ;; *) die "Invalid hostname mode";; esac
  case "$WFS_RDP_PASSWORD_MODE" in random_each_run|same_from_secret) ;; *) die "Invalid RDP password mode";; esac
  case "$WFS_VNC_PASSWORD_MODE" in random_each_run|same_from_secret) ;; *) die "Invalid VNC password mode";; esac
  [[ "$WFS_HOSTNAME_BASE" =~ ^[a-z][a-z0-9-]{0,39}$ ]] || die "Hostname must be 1–40 chars: lowercase letters, numbers and hyphens."
  [[ "$WFS_RDP_USERNAME" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || die "Invalid Linux RDP username."
  [[ "$WFS_WEB_USERNAME" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || die "Invalid Linux web username."
  if [ "$WFS_DISTRO" = arch ] && [ "$WFS_REMOTE" != novnc ]; then
    die "Arch xrdp requires AUR; choose Debian/Ubuntu/Fedora/Alpine for native RDP or novnc for Arch."
  fi
  case "$WFS_REMOTE" in rdp|novnc|both) ;; *) die "Invalid remote choice";; esac
  if [ "$WFS_DISTRO" = arch ] && [ "$WFS_REMOTE" != novnc ]; then
    die "Native xrdp for Arch is not packaged upstream; choose Debian/Ubuntu/Fedora/Alpine for RDP or use novnc."
  fi
}
prepare() {
  validate
  umask 077
  mkdir -p "$config"
  chmod 700 "$state"
  export WFS_PASSWORD_DIR="$state"
  # Passwords for random_each_run are deterministic per run, but never shown
  # in public GitHub Actions logs. Users derive them locally with their
  # existing secret and run ID; see README.
  python3 - <<'PY'
import hashlib, hmac, os, pathlib, re
root = pathlib.Path(os.environ["WFS_PASSWORD_DIR"])
run = os.environ["GITHUB_RUN_ID"]
checks = [
    ("rdp", "WFS_RDP_PASSWORD", "WFS_RDP_PASSWORD_MODE", "rdp-password"),
    ("web", "WFS_VNC_PASSWORD", "WFS_VNC_PASSWORD_MODE", "web-password"),
]
remote = os.environ["WFS_REMOTE"]
for label, key, setting, file in checks:
    needed = (label == "rdp" and remote in ("rdp", "both")) or (
        label == "web" and remote in ("novnc", "both"))
    if not needed:
        continue
    original = os.environ.get(key, "")
    if len(original.encode("utf8")) < 8 or "\n" in original or "\r" in original:
        raise SystemExit(f"{key} secret must have 8+ bytes, without newlines.")
    mode = os.environ[setting]
    password = original if mode == "same_from_secret" else hmac.new(
        original.encode("utf8"), f"wfs:{run}:{label}".encode("utf8"),
        hashlib.sha256).hexdigest()[:24]
    dest = root / file
    dest.write_text(password, encoding="utf8")
    dest.chmod(0o600)
    print(f"[WFS Linux] {label} password mode={mode}, credentials masked (never logged).")
# Webtop always runs internally; RDP-only never exposes browser port.
if remote == "rdp":
    dest = root / "web-password"
    dest.write_bytes((root / "rdp-password").read_bytes())
    dest.chmod(0o600)
PY
  local hostname="$WFS_HOSTNAME_BASE"
  if [ "$WFS_HOSTNAME_MODE" = unique_each_run ]; then
    hostname="${WFS_HOSTNAME_BASE}-${GITHUB_RUN_ID}"
  fi
  echo "WFS_HOSTNAME=$hostname" >> "$GITHUB_ENV"
  notice "Runner hostname=$hostname, xrdp user=$WFS_RDP_USERNAME, web user=$WFS_WEB_USERNAME, remote=$WFS_REMOTE."
  notice "Using existing RDP_PASSWORD and VNC_PASSWORD GitHub secrets only."
}

start() {
  validate
  [ -s "$password_file" ] || die "Password file missing."
  local image="lscr.io/linuxserver/webtop:$WFS_DISTRO-$WFS_DESKTOP"
  notice "Pulling $image"
  docker pull "$image"
  docker rm -f "$name" >/dev/null 2>&1 || true
  local -a rdp_args=()
  if [ "$WFS_REMOTE" = rdp ] || [ "$WFS_REMOTE" = both ]; then
    [ -s "$rdp_password_file" ] || die "RDP password file missing."
    rdp_args=(-p 127.0.0.1:13389:3389 --mount "type=bind,src=$rdp_password_file,dst=/run/secrets/rdp_password,readonly")
  fi
  docker run -d --name "$name" --shm-size=1g --memory=8g --cpus=3 --restart=no \
    -p 127.0.0.1:13001:3001 -p 127.0.0.1:13000:3000 "${rdp_args[@]}" \
    --mount "type=bind,src=$config,dst=/config" \
    --mount "type=bind,src=$password_file,dst=/run/secrets/web_password,readonly" \
    -e "PUID=$(id -u)" -e "PGID=$(id -g)" \
    -e TZ=Etc/UTC -e "CUSTOM_USER=$WFS_WEB_USERNAME" -e FILE__PASSWORD=/run/secrets/web_password \
    -e SELKIES_ENABLE_RESIZE=true -e SELKIES_MANUAL_RESOLUTION=false \
    -e SELKIES_USE_CSS_SCALING=false "$image" >/dev/null
  local code=""
  for attempt in $(seq 1 80); do
    if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)" != true ]; then
      docker logs --tail 60 "$name" || true
      die "Webtop container exited during startup."
    fi
    code=$(curl --insecure --silent --location --output /dev/null --write-out '%{http_code}' \
      --max-time 5 --user "$WFS_WEB_USERNAME:$(cat "$password_file")" https://127.0.0.1:13001/ || true)
    if [ "$code" = 200 ]; then break; fi
    sleep 3
  done
  [ "$code" = 200 ] || { docker logs --tail 60 "$name" || true; die "Backend HTTP response: $code (expected 200)."; }
  notice "Authenticated desktop backend passed HTTP 200 on localhost."
  echo "WFS_IMAGE=$image" >> "$GITHUB_ENV"
  echo "WFS_IMAGE_ID=$(docker image inspect --format '{{.Id}}' "$image")" >> "$GITHUB_ENV"
}
probe() {
  local url="$1" trust="$2" code=""
  for attempt in 1 2 3; do
    if [ "$trust" = selfsigned ]; then
      code=$(curl --insecure --silent --location --output /dev/null --write-out '%{http_code}' \
        --connect-timeout 8 --max-time 15 --user "$WFS_WEB_USERNAME:$(cat "$password_file")" "$url" || true)
    else
      code=$(curl --silent --location --output /dev/null --write-out '%{http_code}' \
        --connect-timeout 8 --max-time 15 --user "$WFS_WEB_USERNAME:$(cat "$password_file")" "$url" || true)
    fi
    [ "$code" = 200 ] && return 0
    sleep 3
  done
  notice "Tailnet self-probe did not return 200 (received $code)."
  return 1
}
publish() {
  validate
  command -v tailscale >/dev/null || die "Tailscale CLI is not installed."
  local ip fqdn="" browser_url="" browser_transport=none rdp_address="" status
  ip=$(tailscale ip -4 | head -1)
  [[ "$ip" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "No Tailscale IPv4."
  timeout 15s tailscale serve reset >/dev/null 2>&1 || true

  if [ "$WFS_REMOTE" = novnc ] || [ "$WFS_REMOTE" = both ]; then
    browser_transport=tailnet_tls_tcp
    if [ "$WFS_TRANSPORT" != tailnet_tls_tcp ]; then
      fqdn=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))')
      if [[ "$fqdn" =~ \.ts\.net$ ]]; then
        notice "Attempting tailnet HTTPS 443 (max 75 seconds)."
        if timeout 75s tailscale serve --bg --yes --https=443 http://127.0.0.1:13000; then
          if probe "https://$fqdn/" trusted; then
            browser_url="https://$fqdn/"
            browser_transport=tailnet_https
          fi
        fi
      fi
      if [ "$browser_transport" != tailnet_https ] && [ "$WFS_TRANSPORT" = tailnet_https ]; then
        die "Trusted Tailscale HTTPS unavailable; choose auto or enable HTTPS Certificates."
      fi
    fi
    if [ "$browser_transport" = tailnet_tls_tcp ]; then
      timeout 15s tailscale serve reset >/dev/null 2>&1 || true
      timeout 30s tailscale serve --bg --yes --tcp=6082 tcp://127.0.0.1:13001
      browser_url="https://$ip:6082/"
      if ! probe "$browser_url" selfsigned; then
        notice "Local Tailscale-IP self-probe failed; checking Serve mapping instead."
      fi
    fi
  fi

  if [ "$WFS_REMOTE" = rdp ] || [ "$WFS_REMOTE" = both ]; then
    [ "${WFS_RDP_READY:-0}" = 1 ] || die "xrdp backend not verified."
    timeout 30s tailscale serve --bg --yes --tcp=3389 tcp://127.0.0.1:13389
    rdp_address="$ip:3389"
  fi

  status=$(timeout 15s tailscale serve status)
  if [ "$WFS_REMOTE" = rdp ] || [ "$WFS_REMOTE" = both ]; then
    [[ "$status" == *3389* && "$status" == *13389* ]] || die "RDP Serve 3389 -> 13389 not verified."
  fi
  if [ "$WFS_REMOTE" = novnc ] || [ "$WFS_REMOTE" = both ]; then
    if [ "$browser_transport" = tailnet_tls_tcp ]; then
      [[ "$status" == *6082* && "$status" == *13001* ]] || die "Web Serve 6082 -> 13001 not verified."
    else
      [[ "$status" == *443* && "$status" == *13000* ]] || die "HTTPS Serve 443 -> 13000 not verified."
    fi
  fi
  {
    echo "WFS_LINUX_IP=$ip"
    echo "WFS_LINUX_URL=$browser_url"
    echo "WFS_RDP_ADDRESS=$rdp_address"
    echo "WFS_ACTIVE_TRANSPORT=$browser_transport"
  } >> "$GITHUB_ENV"
  notice "Tailscale private RDP: ${rdp_address:-disabled}. Web: ${browser_url:-disabled}."
  notice "Credentials: $WFS_RDP_USERNAME / RDP_PASSWORD and $WFS_WEB_USERNAME / VNC_PASSWORD (mode in Summary)."
  [ -z "$browser_url" ] || echo "::notice title=Linux Web Remote::$browser_url"
  [ -z "$rdp_address" ] || echo "::notice title=Linux Native RDP::$rdp_address"
}

summary() {
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
## 🐧 Linux Remote Workspace — READY

| Setting | Value |
|:--|:--|
| Distro / desktop | **$WFS_DISTRO / $WFS_DESKTOP** |
| Image | $WFS_IMAGE |
| Remote choice | **$WFS_REMOTE** |
| Tailscale hostname | **$WFS_HOSTNAME** |
| **Native RDP address (mstsc)** | ${WFS_RDP_ADDRESS:-Not enabled} |
| RDP username | **$WFS_RDP_USERNAME** |
| RDP password | **$WFS_RDP_PASSWORD_MODE** from RDP_PASSWORD |
| **Browser address (Selkies/noVNC equivalent)** | ${WFS_LINUX_URL:-Not enabled} |
| Browser username | **$WFS_WEB_USERNAME** |
| Browser password | **$WFS_VNC_PASSWORD_MODE** from VNC_PASSWORD |
| Web transport | ${WFS_ACTIVE_TRANSPORT:-none} |
| Browser resolution | Automatic Selkies resizing |
| Optional apps | $WFS_APPS |
| Selected duration | $WFS_DURATION hour(s), GitHub job maximum 360 minutes |

**RDP and browser are separate desktop sessions.**
Both endpoints are restricted to the Tailscale tailnet.
EOF
  if [ "${WFS_ACTIVE_TRANSPORT:-none}" = tailnet_tls_tcp ]; then
    echo 'The browser fallback on TCP 6082 uses a self-signed HTTPS certificate. Use trusted HTTPS 443 to avoid a certificate warning.' >> "$GITHUB_STEP_SUMMARY"
  fi
  if [ -f "$state/apps-status.tsv" ]; then
    {
      echo
      echo '### Selected applications'
      echo '| App | Status |'
      echo '|:--|:--|'
      while IFS=$'\t' read -r app result; do
        printf '| %s | %s |\n' "$app" "$result"
      done < "$state/apps-status.tsv"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  echo 'The selected distro runs inside a temporary container on GitHub Ubuntu 24.04. Do not terminate the runner; use Disconnect or Cancel workflow.' >> "$GITHUB_STEP_SUMMARY"
}

keepalive() {
  validate
  local deadline=$((SECONDS + WFS_DURATION * 3600))
  notice "Keep Alive started ($WFS_DURATION hours requested; overall job max 360 minutes)."
  while [ "$SECONDS" -lt "$deadline" ]; do
    [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)" = true ] || die "Desktop container stopped."
    tailscale status --json >/dev/null || die "Tailscale is offline."
    notice "Heartbeat: $WFS_DISTRO/$WFS_DESKTOP running at $(date -u '+%H:%M:%S UTC')."
    sleep 60
  done
  notice "Session duration completed."
}
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  rm -rf "$state"
  notice "Container/secret cleaned up. Tailscale GitHub Action logs out in its post-step."
}
case "$1" in
  prepare) prepare;; start) start;; publish) publish;; summary) summary;;
  keepalive) keepalive;; cleanup) cleanup;; *) die "Usage: workspace.sh prepare|start|publish|summary|keepalive|cleanup";;
esac
