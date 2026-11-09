#!/usr/bin/env bash
# Mandatory Chrome / Chromium with Windows-parity extension policies.
# Same Chrome Web Store IDs as the repository's Windows workflow:
# Cookie-Editor and GoFullPage. Policies apply to every local Linux user.
set -Eeuo pipefail
die() { echo "::error::[WFS Chrome] $*" >&2; exit 1; }
say() { echo "[WFS Chrome] $*"; }
docker inspect wfs-linux-webtop >/dev/null || die "Desktop container missing"
say "Installing Google Chrome (or distro Chromium fallback) and mandatory Cookie-Editor + GoFullPage policies."
docker exec -i -u 0 wfs-linux-webtop /bin/sh -s -- "$WFS_DISTRO" <<'IN_CONTAINER'
set -eu
distro="$1"
export DEBIAN_FRONTEND=noninteractive
case "$distro" in
  ubuntu|debian)
    if ! command -v google-chrome-stable >/dev/null 2>&1; then
      apt-get update -qq
      apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg
      curl -fsSL --retry 3 --connect-timeout 20 https://dl.google.com/linux/linux_signing_key.pub |
        gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
      printf '%s\n' 'deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main' \
        > /etc/apt/sources.list.d/google-chrome.list
      apt-get update -qq
      apt-get install -y -qq --no-install-recommends google-chrome-stable
    fi
    browser=google-chrome-stable
    policy_dir=/etc/opt/chrome/policies/managed
    ;;
  fedora)
    if ! command -v google-chrome-stable >/dev/null 2>&1; then
      cat > /etc/yum.repos.d/google-chrome.repo <<'REPO'
[google-chrome]
name=Google Chrome - $basearch
baseurl=https://dl.google.com/linux/chrome/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
REPO
      dnf install -y google-chrome-stable
    fi
    browser=google-chrome-stable
    policy_dir=/etc/opt/chrome/policies/managed
    ;;
  arch)
    pacman -Sy --needed --noconfirm chromium
    browser=chromium
    policy_dir=/etc/chromium/policies/managed
    ;;
  alpine)
    apk add --no-cache chromium
    browser=chromium
    policy_dir=/etc/chromium/policies/managed
    ;;
  *)
    echo "Unsupported distro for Chrome" >&2
    exit 20
    ;;
esac
command -v "$browser" >/dev/null 2>&1 || { echo "Google Chrome / Chromium executable not found" >&2; exit 21; }
mkdir -p "$policy_dir"
# These extension IDs are identical to Windows; Chrome Enterprise policy
# downloads them from the official Chrome Web Store on browser startup.
cat > "$policy_dir/wfs-required-extensions.json" <<'POLICY'
{
  "ExtensionInstallForcelist": [
    "hlkenndednhfkekhgcdicdfddnkalmdm;https://clients2.google.com/service/update2/crx",
    "fdpohaocaechififmbbbbbknoalclacl;https://clients2.google.com/service/update2/crx"
  ]
}
POLICY
chmod 644 "$policy_dir/wfs-required-extensions.json"
# Validate exact policy content and JSON syntax before reporting browser ready.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$policy_dir/wfs-required-extensions.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data=json.load(f)
items=data["ExtensionInstallForcelist"]
ids=[x.split(";")[0] for x in items]
assert ids==["hlkenndednhfkekhgcdicdfddnkalmdm", "fdpohaocaechififmbbbbbknoalclacl"]
assert all(x.endswith(";https://clients2.google.com/service/update2/crx") for x in items)
print("PASS: valid Chrome managed policy: Cookie-Editor + GoFullPage.")
PY
else
  grep -Fq 'hlkenndednhfkekhgcdicdfddnkalmdm' "$policy_dir/wfs-required-extensions.json"
  grep -Fq 'fdpohaocaechififmbbbbbknoalclacl' "$policy_dir/wfs-required-extensions.json"
fi
"$browser" --version
mkdir -p /usr/share/applications
cat > /usr/share/applications/wfs-google-chrome.desktop <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Chrome (WFS)
Comment=Browser with mandatory Cookie-Editor and GoFullPage policies
Exec=$browser %U
Terminal=false
Categories=Network;WebBrowser;
EOF
echo "[WFS Chrome] PASS: browser executable, desktop shortcut and two Windows-parity extension policies."
echo "[WFS Chrome] Extension CRX downloads occur when a Chrome user profile starts; internet and Web Store must be reachable."
IN_CONTAINER
echo "WFS_CHROME_READY=1" >> "$GITHUB_ENV"
say "Chrome/Chromium installed. Cookie-Editor + GoFullPage force-install policy configured for all users."
