#!/usr/bin/env bash
# Optional ArtCraft Launcher from upstream official GitHub stable release.
# Verify release metadata and binary SHA-256 before native package installation.
set -Eeuo pipefail
distro="$WFS_DISTRO"
case "$distro" in
  ubuntu|debian) format=deb ;;
  fedora) format=rpm ;;
  arch) format=pkg.tar.zst ;;
  alpine)
    echo "::warning::ArtCraft Launcher does not publish an Alpine musl-native package; skipping rather than installing an incompatible glibc build."
    exit 0 ;;
  *) echo "::error::Unsupported distro: $distro"; exit 1 ;;
esac
output="$RUNNER_TEMP/wfs-artcraft.$format"
export WFS_ARTCRAFT_FORMAT="$format" WFS_ARTCRAFT_FILE="$output"
echo "[WFS Linux] Checking official ArtCraft Launcher stable release for $distro."
python3 - <<'PY'
import hashlib, json, os, re, urllib.request
api = "https://api.github.com/repos/storytold/craft-launcher/releases/latest"
headers = {"User-Agent": "WFS-Linux-Remote-Workspace", "Accept": "application/vnd.github+json"}
with urllib.request.urlopen(urllib.request.Request(api, headers=headers), timeout=35) as res:
    release = json.load(res)
if release.get("draft") or release.get("prerelease"):
    raise SystemExit("The latest official release is not stable.")
tag = str(release.get("tag_name", ""))
if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
    raise SystemExit("Unexpected official release version.")
version = tag[1:]
format_ = os.environ["WFS_ARTCRAFT_FORMAT"]
name = f"artcraft-launcher-{version}-linux-x86_64.{format_}"
assets = [asset for asset in release.get("assets", []) if asset.get("name") == name]
if len(assets) != 1:
    raise SystemExit(f"No official {format_} asset for ArtCraft {tag}.")
asset = assets[0]
expected_url = f"https://github.com/storytold/craft-launcher/releases/download/{tag}/{name}"
if asset.get("browser_download_url") != expected_url:
    raise SystemExit("Release asset URL does not match upstream GitHub repository.")
digest = str(asset.get("digest", ""))
if not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
    raise SystemExit("Release asset is missing a valid SHA256 digest.")
expected_len = int(asset.get("size", 0))
if not 1_000_000 <= expected_len <= 250_000_000:
    raise SystemExit("Release asset size is outside the expected range.")
target = os.environ["WFS_ARTCRAFT_FILE"]
hash_ = hashlib.sha256()
total = 0
req = urllib.request.Request(expected_url, headers={"User-Agent": "WFS-Linux-Remote-Workspace"})
with urllib.request.urlopen(req, timeout=120) as res, open(target, "wb") as stream:
    while True:
        chunk = res.read(1024 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > expected_len:
            raise SystemExit("Downloaded asset is larger than upstream metadata.")
        hash_.update(chunk)
        stream.write(chunk)
if total != expected_len or hash_.hexdigest().lower() != digest[7:].lower():
    os.unlink(target)
    raise SystemExit("ArtCraft downloaded package failed official size/SHA256 verification.")
print(f"[WFS Linux] Verified ArtCraft Launcher {tag}: SHA256 and asset size match upstream GitHub.")
PY

trap 'rm -f "$output"' EXIT
docker cp "$output" "wfs-linux-webtop:/tmp/wfs-artcraft.$format"
echo "[WFS Linux] Installing the verified native package inside the $distro container."
case "$distro" in
  debian|ubuntu)
    docker exec -u 0 wfs-linux-webtop /bin/sh -c \
      'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/wfs-artcraft.deb' ;;
  fedora)
    docker exec -u 0 wfs-linux-webtop /bin/sh -c \
      'dnf -y install /tmp/wfs-artcraft.rpm' ;;
  arch)
    docker exec -u 0 wfs-linux-webtop /bin/sh -c \
      'pacman -Syu --noconfirm && pacman -U --noconfirm /tmp/wfs-artcraft.pkg.tar.zst' ;;
esac
echo "[WFS Linux] ArtCraft Launcher package installed. Launch it from the Linux applications menu."
