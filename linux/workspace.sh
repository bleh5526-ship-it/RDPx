#!/usr/bin/env bash
# WFS Linux Remote Workspace. Browser desktops stay private to Tailscale.
set -Eeuo pipefail
name=wfs-linux-webtop
state="$RUNNER_TEMP/wfs-linux"
config="$state/config"
password_file="$state/web-password"
notice() { printf '[WFS Linux] %s\n' "$*"; }
die() { echo "::error::$*" >&2; exit 1; }
validate() {
  case "$WFS_DISTRO" in ubuntu|debian|fedora|arch|alpine) ;; *) die "Unsupported Linux distro: $WFS_DISTRO";; esac
  case "$WFS_DESKTOP" in xfce|kde|mate|i3) ;; *) die "Unsupported desktop: $WFS_DESKTOP";; esac
  case "$WFS_DURATION" in 1|3|6) ;; *) die "Invalid duration";; esac
  case "$WFS_TRANSPORT" in auto|tailnet_https|tailnet_tls_tcp) ;; *) die "Invalid transport";; esac
  case "$WFS_APPS" in none|developer|office|media|all) ;; *) die "Invalid app bundle";; esac
}
prepare() {
  validate
  [ -n "$WFS_DESKTOP_PASSWORD" ] || die "Create secret LINUX_DESKTOP_PASSWORD first."
  [ "$(printf '%s' "$WFS_DESKTOP_PASSWORD" | wc -c)" -ge 12 ] || die "Desktop password must be >=12 bytes."
  umask 077
  mkdir -p "$config"
  chmod 700 "$state"
  printf '%s' "$WFS_DESKTOP_PASSWORD" > "$password_file"
  chmod 600 "$password_file"
  notice "Configuration validated: $WFS_DISTRO / $WFS_DESKTOP; secret kept off logs."
}
start() {
  validate
  [ -s "$password_file" ] || die "Password file missing."
  local image="lscr.io/linuxserver/webtop:$WFS_DISTRO-$WFS_DESKTOP"
  notice "Pulling $image"
  docker pull "$image"
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --name "$name" --shm-size=1g --memory=8g --cpus=3 --restart=no \
    -p 127.0.0.1:13001:3001 -p 127.0.0.1:13000:3000 \
    --mount "type=bind,src=$config,dst=/config" \
    --mount "type=bind,src=$password_file,dst=/run/secrets/web_password,readonly" \
    -e "PUID=$(id -u)" -e "PGID=$(id -g)" \
    -e TZ=Etc/UTC -e CUSTOM_USER=wfs -e FILE__PASSWORD=/run/secrets/web_password \
    -e SELKIES_ENABLE_RESIZE=true -e SELKIES_MANUAL_RESOLUTION=false \
    -e SELKIES_USE_CSS_SCALING=false "$image" >/dev/null
  local code=""
  for attempt in $(seq 1 80); do
    if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)" != true ]; then
      docker logs --tail 60 "$name" || true
      die "Webtop container exited during startup."
    fi
    code=$(curl --insecure --silent --location --output /dev/null --write-out '%{http_code}' \
      --max-time 5 --user "wfs:$(cat "$password_file")" https://127.0.0.1:13001/ || true)
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
        --connect-timeout 8 --max-time 15 --user "wfs:$(cat "$password_file")" "$url" || true)
    else
      code=$(curl --silent --location --output /dev/null --write-out '%{http_code}' \
        --connect-timeout 8 --max-time 15 --user "wfs:$(cat "$password_file")" "$url" || true)
    fi
    [ "$code" = 200 ] && return 0
    sleep 3
  done
  notice "Tailnet self-probe did not return 200 (received $code)."
  return 1
}
publish() {
  validate
  command -v tailscale >/dev/null || die "Tailscale CLI missing."
  local ip fqdn="" url="" transport=tailnet_tls_tcp
  ip=$(tailscale ip -4 | head -1)
  [[ "$ip" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Tailscale IPv4 missing."
  timeout 15s tailscale serve reset >/dev/null 2>&1 || true
  if [ "$WFS_TRANSPORT" != tailnet_tls_tcp ]; then
    fqdn=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))')
    if [[ "$fqdn" =~ \.ts\.net$ ]]; then
      notice "Attempting trusted Tailscale HTTPS on 443 (75-second limit)."
      if timeout 75s tailscale serve --bg --yes --https=443 http://127.0.0.1:13000; then
        if probe "https://$fqdn/" trusted; then
          url="https://$fqdn/"
          transport=tailnet_https
        fi
      fi
    fi
    if [ "$transport" != tailnet_https ] && [ "$WFS_TRANSPORT" = tailnet_https ]; then
      die "Tailscale HTTPS/certificate unavailable. Enable MagicDNS+HTTPS or choose auto."
    fi
  fi
  if [ "$transport" = tailnet_tls_tcp ]; then
    notice "Using private TLS-over-Tailscale TCP port 6082 (self-signed Webtop certificate)."
    timeout 15s tailscale serve reset >/dev/null 2>&1 || true
    timeout 30s tailscale serve --bg --yes --tcp=6082 tcp://127.0.0.1:13001
    local serve_state
    serve_state=$(timeout 15s tailscale serve status || true)
    [[ "$serve_state" == *6082* && "$serve_state" == *13001* ]] ||
      die "TCP Serve was not mapped from port 6082 to localhost:13001."
    url="https://$ip:6082/"
    if ! probe "$url" selfsigned; then
      notice "Warning: self-probe over own Tailscale IP failed, despite verified Serve mapping. External-client reachability is NOT verified."
    fi
  fi
  echo "WFS_LINUX_URL=$url" >> "$GITHUB_ENV"
  echo "WFS_LINUX_IP=$ip" >> "$GITHUB_ENV"
  echo "WFS_ACTIVE_TRANSPORT=$transport" >> "$GITHUB_ENV"
  notice "Private browser URL: $url"
  notice "Transport: $transport. No Cloudflare or Funnel."
  echo "::notice title=Linux private desktop::$url"
}
summary() {
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
## Linux Remote Workspace — READY

| Setting | Value |
|:--|:--|
| Distro / desktop | **$WFS_DISTRO / $WFS_DESKTOP** |
| Image | $WFS_IMAGE |
| Private browser URL | **$WFS_LINUX_URL** |
| Tailscale IP | $WFS_LINUX_IP |
| Transport | $WFS_ACTIVE_TRANSPORT |
| Username | **wfs** |
| Password | Secret LINUX_DESKTOP_PASSWORD (never printed) |
| Scaling | Automatic (Selkies resize) |
| Optional apps | $WFS_APPS |
| Selected duration | $WFS_DURATION hour(s), max 360 minutes including setup |

Open this URL on a device connected to the same Tailscale tailnet.
EOF
  if [ "$WFS_ACTIVE_TRANSPORT" = tailnet_tls_tcp ]; then
    echo "**Certificate warning:** this fallback uses Webtop HTTPS with a self-signed certificate inside encrypted Tailscale TCP 6082. The browser may require manual acceptance once. Enable tailnet HTTPS Certificates and choose tailnet_https to avoid the warning." >> "$GITHUB_STEP_SUMMARY"
  fi
  echo "The selected distro runs in a Docker container on the GitHub-hosted Ubuntu 24.04 runner. Closing the browser does not end the session." >> "$GITHUB_STEP_SUMMARY"
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
