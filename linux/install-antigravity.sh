#!/usr/bin/env bash
# Install the current officially published Antigravity IDE Linux x64 tarball.
# Source link is the Google Antigravity download page; no third-party mirrors.
set -Eeuo pipefail
case "$WFS_DISTRO" in alpine) echo "Alpine musl cannot run this glibc-only Antigravity IDE build." >&2; exit 2 ;; esac
dir="$RUNNER_TEMP/wfs-antigravity-download"
mkdir -p "$dir"
trap 'rm -rf "$dir"' EXIT
# Official Google Linux x64 IDE 2.6.0 URL, as published Nov 9 2026.
# This release has no published independent SHA256 checksum; HTTPS protects
# download integrity and binary availability is verified after extraction.
url='https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.6.0-5526304964083712/linux-x64/Antigravity%20IDE.tar.gz'
echo "[WFS Antigravity] Downloading official Linux x64 IDE v2.6.0 from Google."
curl --fail --location --silent --show-error --retry 3 --connect-timeout 20 \
  --max-time 230 --max-filesize 650000000 "$url" -o "$dir/antigravity-ide.tar.gz"
test "$(stat -c %s "$dir/antigravity-ide.tar.gz")" -ge 5000000
# Check paths before root extraction (prevent path traversal by archive).
python3 - "$dir/antigravity-ide.tar.gz" <<'PY'
import pathlib, sys, tarfile
path = sys.argv[1]
with tarfile.open(path, "r:gz") as tar:
    members = tar.getmembers()
    if not members:
        raise SystemExit("Empty official Antigravity archive")
    for member in members:
        parts = pathlib.PurePosixPath(member.name).parts
        if member.name.startswith("/") or ".." in parts:
            raise SystemExit("Unsafe archive path")
print(f"[WFS Antigravity] Archive verified and contains {len(members)} entries.")
PY
docker cp "$dir/antigravity-ide.tar.gz" wfs-linux-webtop:/tmp/wfs-antigravity-ide.tar.gz
docker exec -u 0 wfs-linux-webtop /bin/sh -s <<'IN_CONTAINER'
set -eu
root=/opt/wfs-antigravity-ide
mkdir -p "$root"
tar -xzf /tmp/wfs-antigravity-ide.tar.gz -C "$root" --no-same-owner
rm -f /tmp/wfs-antigravity-ide.tar.gz
exe=$(find "$root" -maxdepth 6 -type f -perm /u=x \( -iname 'antigravity' -o -iname 'antigravity-ide' -o -iname 'Antigravity IDE' \) -print -quit)
if [ -z "$exe" ]; then
  echo "[WFS Antigravity] Executable was not found in the official tarball" >&2
  exit 1
fi
ln -sf "$exe" /usr/local/bin/antigravity-ide
mkdir -p /usr/share/applications
cat > /usr/share/applications/wfs-antigravity-ide.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Antigravity IDE
Comment=Google Antigravity IDE (official Linux build)
Exec=/usr/local/bin/antigravity-ide
Terminal=false
Categories=Development;IDE;
EOF
test -x /usr/local/bin/antigravity-ide
echo "[WFS Antigravity] PASS: launcher installed and executable verified: $exe"
IN_CONTAINER
