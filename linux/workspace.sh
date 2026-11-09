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
  # Normalize Windows-style uppercase "RDP" into a real Linux account name.
  if [ "$WFS_RDP_USERNAME" != "${WFS_RDP_USERNAME,,}" ]; then
    WFS_RDP_USERNAME="${WFS_RDP_USERNAME,,}"
    echo "WFS_RDP_USERNAME=$WFS_RDP_USERNAME" >> "$GITHUB_ENV"
    notice "Normalized the RDP username to lowercase: $WFS_RDP_USERNAME."
  fi
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
  notice "🔐 [1/5] Configuration accepted: hostname=$hostname, RDP user=$WFS_RDP_USERNAME, web user=$WFS_WEB_USERNAME, mode=$WFS_REMOTE."
  notice "Using existing RDP_PASSWORD and VNC_PASSWORD GitHub secrets only."
}

start() {
  validate
  [ -s "$password_file" ] || die "Password file missing."
  local image="lscr.io/linuxserver/webtop:$WFS_DISTRO-$WFS_DESKTOP"
  notice "🐧 [2/5] Downloading selected desktop image: $image"
  # Registry throttling is intermittent on GitHub-hosted runners.
  # Retry a small bounded number of times, without changing the selected tag.
  local pulled=no
  for attempt in 1 2 3 4; do
    if docker pull "$image"; then pulled=yes; break; fi
    notice "⚠️ Webtop registry pull failed attempt $attempt/4; retrying."
    sleep $((attempt * 5))
  done
  [ "$pulled" = yes ] || die "Cannot pull $image after four attempts (check registry rate limits)."
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
  notice "✅ [2/5] Webtop desktop healthy: authenticated HTTPS 200 on localhost, private Docker ports only."
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
# Bind the fallback to the Tailscale 100.x interface only.
# Tailscale Serve is optional; the tailnet itself remains required.
start_tailnet_forwarder() {
  local ip="$1" public_port="$2" local_port="$3"
  local logfile="$state/forward-$public_port.log"
  if ! command -v socat >/dev/null 2>&1; then
    notice "Installing socat for private tailnet port forwarding."
    timeout 95s sudo -n apt-get install -y -qq --no-install-recommends socat >/dev/null ||
      die "Cannot install socat for private tailnet forwarding."
  fi
  if ! ip -4 addr show | grep -Fq "inet $ip/"; then
    die "Tailscale IPv4 $ip not assigned to a local interface; direct tailnet forwarding unavailable."
  fi
  nohup socat "TCP-LISTEN:$public_port,bind=$ip,reuseaddr,fork" \
    "TCP:127.0.0.1:$local_port,connect-timeout=8" \
    > "$logfile" 2>&1 < /dev/null &
  local pid=$!
  echo "$pid" >> "$state/forwarder-pids"
  sleep 2
  kill -0 "$pid" 2>/dev/null ||
    { cat "$logfile" >&2 || true; die "Tailnet TCP forwarder exited: $ip:$public_port"; }
  python3 - "$ip" "$public_port" <<'PY'
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
with socket.create_connection((host, port), timeout=5):
    print(f"[WFS Linux] PASS: tailnet-only listener reachable on {host}:{port}")
PY
  notice "Tailnet-only TCP forwarder: $ip:$public_port -> 127.0.0.1:$local_port (pid $pid)."
}

publish() {
  validate
  command -v tailscale >/dev/null || die "Tailscale CLI is not installed."
  local ip fqdn="" browser_url="" browser_transport=none rdp_address=""
  ip=$(tailscale ip -4 | head -1)
  [[ "$ip" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "No Tailscale IPv4."
  tailscale status --json >/dev/null || die "Tailscale is not connected."

  if [ "$WFS_REMOTE" = novnc ] || [ "$WFS_REMOTE" = both ]; then
    if [ "$WFS_TRANSPORT" != tailnet_tls_tcp ]; then
      fqdn=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))')
      if [[ "$fqdn" =~ \.ts\.net$ ]]; then
        notice "Trying optional Tailscale HTTPS Serve 443 (max 12 seconds)."
        if timeout 12s sudo -n tailscale serve --bg --yes --https=443 http://127.0.0.1:13000 >/dev/null 2>&1; then
          if probe "https://$fqdn/" trusted; then
            browser_url="https://$fqdn/"
            browser_transport=tailnet_https
          fi
        fi
      fi
      if [ "$browser_transport" != tailnet_https ] && [ "$WFS_TRANSPORT" = tailnet_https ]; then
        die "Tailscale HTTPS requires admin-enabled Serve and HTTPS Certificates. Choose auto or tailnet_tls_tcp for private-IP fallback."
      fi
    fi
    if [ "$browser_transport" != tailnet_https ]; then
      # Admin consent for Serve is NOT required for a port bound to the
      # machine's Tailscale IP. The app itself still requires web auth.
      start_tailnet_forwarder "$ip" 6082 13001
      browser_url="https://$ip:6082/"
      browser_transport=tailnet_tls_tcp
      probe "$browser_url" selfsigned ||
        die "Authenticated Webtop HTTPS did not respond on the private tailnet-IP forwarder."
    fi
  fi

  if [ "$WFS_REMOTE" = rdp ] || [ "$WFS_REMOTE" = both ]; then
    [ "${WFS_RDP_READY:-0}" = 1 ] || die "Native xrdp was not verified."
    start_tailnet_forwarder "$ip" 3389 13389
    rdp_address="$ip:3389"
  fi

  {
    echo "WFS_LINUX_IP=$ip"
    echo "WFS_LINUX_URL=$browser_url"
    echo "WFS_RDP_ADDRESS=$rdp_address"
    echo "WFS_ACTIVE_TRANSPORT=$browser_transport"
  } >> "$GITHUB_ENV"
  notice "✅ [4/5] Private endpoints: RDP=${rdp_address:-disabled}; browser=${browser_url:-disabled}."
  notice "Forwarded ports bind to Tailscale 100.x only; no public listener or Funnel."
  [ -z "$browser_url" ] || echo "::notice title=Linux Web Remote::$browser_url"
  [ -z "$rdp_address" ] || echo "::notice title=Linux Native RDP::$rdp_address"
}

summary() {
  local rdp_state="⏭️ Not selected" web_state="⏭️ Not selected"
  local transport_label="Not selected" artcraft_state="⏭️ Not selected"
  local apps_state="⏭️ Not selected"
  local image_digest="${WFS_IMAGE_ID:-not recorded}"
  local run_url="https://github.com/${GITHUB_REPOSITORY:-wawanwfs/RDP}/actions/runs/${GITHUB_RUN_ID:-0}"
  local rdp_url="${WFS_RDP_ADDRESS:-}"
  local web_url="${WFS_LINUX_URL:-}"
  local ip="${WFS_LINUX_IP:-not assigned}"
  local transport="${WFS_ACTIVE_TRANSPORT:-none}"
  local app_step="${WFS_APPS_STEP_OUTCOME:-skipped}"
  local artcraft_step="${WFS_ARTCRAFT_STEP_OUTCOME:-skipped}"
  local artcraft_selected="${WFS_ARTCRAFT_SELECTED:-false}"

  if [ "$WFS_REMOTE" = rdp ] || [ "$WFS_REMOTE" = both ]; then
    rdp_state="✅ xrdp X.224 handshake + private TCP listener verified (GUI login not tested)"
  fi
  if [ "$WFS_REMOTE" = novnc ] || [ "$WFS_REMOTE" = both ]; then
    web_state="✅ Webtop HTTPS HTTP 200 with authentication, verified from runner"
  fi
  case "$transport" in
    tailnet_https) transport_label="✅ Tailscale Serve HTTPS 443 — verified certificate" ;;
    tailnet_tls_tcp) transport_label="✅ Direct Tailscale IP TCP 6082 → Webtop HTTPS (self-signed)" ;;
    none) transport_label="Not selected" ;;
    *) transport_label="⚠️ Unknown: $transport" ;;
  esac
  case "$app_step" in
    success) apps_state="✅ Step completed; see individual app results below" ;;
    failure) apps_state="⚠️ Step failed; desktop remote remains available" ;;
    skipped) apps_state="⏭️ Not selected" ;;
    *) apps_state="ℹ️ $app_step" ;;
  esac
  if [ "$artcraft_selected" = true ]; then
    if [ "$WFS_DISTRO" = alpine ]; then
      artcraft_state="⚠️ Unsupported on Alpine (no native package)"
    else
      case "$artcraft_step" in
        success) artcraft_state="✅ Installer step completed; launch app to verify GUI" ;;
        failure) artcraft_state="❌ Installer step failed; see ArtCraft step log" ;;
        *) artcraft_state="⚠️ Installer step not executed: $artcraft_step" ;;
      esac
    fi
  fi

  # All interpolated metadata below comes from validated workflow choices,
  # trusted GitHub runner variables, and previously verified Tailscale status.
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
# 🐧 WFS Linux Remote Workspace Dashboard

> ✅ **REMOTE READY — private Tailscale connection configured.** Desktop services are responding from the runner. Check the URL from this active run; external-device login is not tested here.

## 🎯 Recommended Login

EOF
  if [ -n "$rdp_url" ]; then
    cat >> "$GITHUB_STEP_SUMMARY" <<EOF
### 🖥️ Microsoft Remote Desktop / xrdp

| RDP access | Connection details |
|:--|:--|
| **RDP address** | \`$rdp_url\` |
| **Username** | \`$WFS_RDP_USERNAME\` |
| **Password** | GitHub Secret \`RDP_PASSWORD\` — \`$WFS_RDP_PASSWORD_MODE\` |
| **Service health** | $rdp_state |
| **Session** | Independent Xorg/Xfce session, separate from web |

**How to connect:** Open Windows \`mstsc\` → enter \`$rdp_url\` → login as \`$WFS_RDP_USERNAME\`.

EOF
  fi
  if [ -n "$web_url" ]; then
    cat >> "$GITHUB_STEP_SUMMARY" <<EOF
### 🌐 Browser Remote / Selkies (noVNC equivalent)

| Browser access | Connection details |
|:--|:--|
| **Open browser desktop** | [$web_url]($web_url) |
| **Username** | \`$WFS_WEB_USERNAME\` |
| **Password** | GitHub Secret \`VNC_PASSWORD\` — \`$WFS_VNC_PASSWORD_MODE\` |
| **Requested transport** | \`$WFS_TRANSPORT\` |
| **Active transport** | $transport_label |
| **Service health** | $web_state |
| **Desktop fit** | Selkies automatic resize; use browser F11 for fullscreen |

EOF
    if [ "$transport" = tailnet_tls_tcp ]; then
      cat >> "$GITHUB_STEP_SUMMARY" <<'EOF'
> ⚠️ **Certificate notice:** port 6082 forwards Webtop's self-signed HTTPS directly over the private Tailscale IP. A browser certificate warning is possible; confirm the address matches this run. Tailscale Serve is **not required** for this fallback.

EOF
    fi
  fi

  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
## 🔗 Connection & Runner Details

| Setting | Value |
|:--|:--|
| GitHub Actions run | [Open this run]($run_url) |
| Distro / desktop | **$WFS_DISTRO / $WFS_DESKTOP** |
| Host runner | Ubuntu 24.04 (ephemeral) |
| Container image | \`${WFS_IMAGE:-unknown}\` |
| Container image digest | \`$image_digest\` |
| **Tailscale hostname** | \`${WFS_HOSTNAME:-unknown}\` |
| **Tailscale IPv4** | \`$ip\` |
| Hostname mode | \`$WFS_HOSTNAME_MODE\` |
| Selected remote | \`$WFS_REMOTE\` |
| Requested browser transport | \`$WFS_TRANSPORT\` |
| Active browser transport | \`$transport\` |
| Browser port | ${web_url:+6082 TCP or 443 HTTPS — private tailnet} |
| RDP port | ${rdp_url:+3389 TCP — private tailnet} |
| Authentication | Separate \`RDP_PASSWORD\` / \`VNC_PASSWORD\` GitHub Secrets; values never shown |
| Session duration | **$WFS_DURATION hour(s)** requested after setup |
| GitHub Actions hard timeout | **360 minutes total**, including preparation |

## 🧪 Service Health

| Health check | Result |
|:--|:--|
| Container & authenticated localhost HTTPS | ✅ Passed |
| Tailscale authenticated node | ✅ Connected |
| Browser HTTPS via private Tailscale endpoint | $web_state |
| Native RDP TCP/X.224 | $rdp_state |
| Port exposure | Bound to runner loopback / Tailscale IP only, not public internet |
| External-device graphical login | ⏳ Not verified — test from your own connected device |

## 📦 Selected Applications & Install Status

| Application group | Selection |
|:--|:--|
| Optional bundle | \`$WFS_APPS\` |
| IDE | \`${WFS_IDE:-none}\` |
| Video editor | \`${WFS_EDITOR:-none}\` |
| MetaTrader | \`${WFS_METATRADER:-none}\` |
| AI router | \`${WFS_ROUTER:-none}\` |
| Coding agent | \`${WFS_CODING_AGENT:-none}\` |
| AI agent | \`${WFS_AI_AGENT:-none}\` |
| ArtCraft Launcher | \`$artcraft_selected\` |

| Install step | Result |
|:--|:--|
| Optional apps | $apps_state |
| ArtCraft Launcher | $artcraft_state |

EOF

  if [ -s "$state/apps-status.tsv" ]; then
    {
      echo '### 🔎 Per-Application Results'
      echo
      echo '| Application | Actual installation status / compatibility |'
      echo '|:--|:--|'
      while IFS=$'\t' read -r app result; do
        # Sanitize Markdown delimiters in package-manager diagnostic fields.
        app=${app//|/\/}
        result=${result//|/\/}
        printf '| %s | %s |\n' "$app" "$result"
      done < "$state/apps-status.tsv"
      echo
    } >> "$GITHUB_STEP_SUMMARY"
  else
    echo '> No per-app installer results were recorded. Optional applications may have been omitted or the installer may not have run.' >> "$GITHUB_STEP_SUMMARY"
    echo >> "$GITHUB_STEP_SUMMARY"
  fi

  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
## 🚀 How to Connect

1. Connect your own PC/mobile device to the **same Tailscale tailnet**.
2. Use the **RDP address** above in Microsoft Remote Desktop, or click the **Browser Remote** URL above (depending on selected access mode).
3. Enter the selected username and password from the relevant GitHub Secret. For \`random_each_run\`, derive the password locally using the [Linux password guide](https://github.com/${GITHUB_REPOSITORY:-wawanwfs/RDP}/blob/main/linux/README.md); random passwords are deliberately **not printed in public logs**.
4. Keep this Actions job running while you are connected. Closing an RDP session or browser tab does not stop the runner.

## 🧯 Troubleshooting

| Problem | What to check |
|:--|:--|
| Hostname does not resolve | Use private Tailscale IP \`$ip\` from **this run** |
| Browser shows HTTPS certificate warning | Expected on self-signed fallback \`6082\`; use trusted Tailscale HTTPS 443 if enabled |
| Browser cannot connect | Tailnet access rules, browser password, selected transport, and the container health step |
| xrdp login fails | Username \`$WFS_RDP_USERNAME\`, \`RDP_PASSWORD\`/password mode, Xorg session logs |
| RDP and browser show different desktops | Expected: xrdp and Selkies run separate sessions |
| Port is unreachable from your device | Verify Tailscale ACL/grants, \`tailscale ping $ip\`, and selected private port |
| Optional application missing | Check the per-app status above and relevant install step logs |
| Session URL stopped working | GitHub Actions run ended/cancelled; ephemeral runner and IP are gone |

## 🧹 Keep Alive & Cleanup

- This workflow intentionally stays **in progress** during a remote session. Keep Alive prints remaining time and health once per minute.
- **1 / 3 / 6 hours** are requested session lengths; the GitHub job has a strict **360-minute total timeout** (setup counts).
- Use **Cancel workflow** to terminate the session. Cleanup stops container, private TCP forwarders, and temporary password files.
- The selected Linux distro is a **container** on Ubuntu, not a separate kernel/VM. Back up anything important before the runner ends.

[📖 Linux setup guide](https://github.com/${GITHUB_REPOSITORY:-wawanwfs/RDP}/blob/main/linux/README.md) · [🪟 Windows workflow](https://github.com/${GITHUB_REPOSITORY:-wawanwfs/RDP}/actions/workflows/windows-remote-workspace-with-apps.yml)
EOF
  notice "✅ Linux Dashboard Summary generated (credentials masked)."
  notice "📊 Actions run: $run_url"
}

keepalive() {
  validate
  local duration=$((WFS_DURATION * 3600))
  local deadline=$((SECONDS + duration))
  local active_web="${WFS_LINUX_URL:-not enabled}"
  local active_rdp="${WFS_RDP_ADDRESS:-not enabled}"
  local session_start
  session_start=$(date -u '+%Y-%m-%d %H:%M UTC')
  cat <<EOF

╔════════════════════════════════════════════════════════════╗
║           🐧 WFS LINUX REMOTE WORKSPACE — READY            ║
╠════════════════════════════════════════════════════════════╣
║  Hostname    : ${WFS_HOSTNAME:-not assigned}
║  Tailscale IP: ${WFS_LINUX_IP:-not assigned}
║  Linux       : $WFS_DISTRO / $WFS_DESKTOP
║  Remote mode : $WFS_REMOTE
║  RDP address : $active_rdp
║  RDP user    : $WFS_RDP_USERNAME (Secret RDP_PASSWORD; $WFS_RDP_PASSWORD_MODE)
║  Web URL     : $active_web
║  Web user    : $WFS_WEB_USERNAME (Secret VNC_PASSWORD; $WFS_VNC_PASSWORD_MODE)
║  Web protocol: ${WFS_ACTIVE_TRANSPORT:-none}
║  Duration    : $WFS_DURATION hour(s) requested
║  Start UTC   : $session_start
╚════════════════════════════════════════════════════════════╝

✅ Tailscale-only connections are ready to test from your device.
🔐 Passwords are NEVER displayed in public Actions logs.
🌐 Webtop browser auto-resizes; use F11 for full screen.
🖥️ RDP (Xorg) and web (Selkies) are separate desktop sessions.
⏳ The total Actions job limit is 360 minutes, including startup.
📊 See the GitHub Actions Summary tab for URLs, applications and diagnostics.

EOF
  notice "Keep Alive running; close RDP/browser client to disconnect, but keep this Actions job active."
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)" != true ]; then
      die "Desktop container stopped while session was active. See Docker logs."
    fi
    if ! tailscale status --json >/dev/null; then
      die "Tailscale disconnected during remote session."
    fi
    local left=$((deadline - SECONDS))
    local minutes=$(((left + 59) / 60))
    notice "🟢 REMOTE READY | $(date -u '+%H:%M:%S UTC') | $minutes min remaining | container=running | tailnet=connected | $WFS_REMOTE"
    local sleep_for=60
    if [ "$left" -lt 60 ]; then sleep_for="$left"; fi
    [ "$sleep_for" -gt 0 ] || break
    sleep "$sleep_for"
  done
  notice "✅ Requested duration completed. Cleanup will stop the temporary remote desktop."
}

cleanup() {
  if [ -f "$state/forwarder-pids" ]; then
    while read -r pid; do
      [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null || true
    done < "$state/forwarder-pids"
  fi
  docker rm -f "$name" >/dev/null 2>&1 || true
  # /config is a bind mount. Package managers and npm create root-owned
  # caches in this disposable directory. Delete ONLY the exact runner-temp
  # workspace with elevated privileges to prevent permission-denied cleanup.
  if [ -n "$RUNNER_TEMP" ] && [ "$state" = "$RUNNER_TEMP/wfs-linux" ] && [ -d "$state" ]; then
    sudo -n rm -rf -- "$state" || die "Cleanup could not delete temporary workspace $state"
  fi
  notice "Container, private TCP forwarders and secret files cleaned up. Tailscale action handles logout."
}
case "$1" in
  prepare) prepare;; start) start;; publish) publish;; summary) summary;;
  keepalive) keepalive;; cleanup) cleanup;; *) die "Usage: workspace.sh prepare|start|publish|summary|keepalive|cleanup";;
esac
