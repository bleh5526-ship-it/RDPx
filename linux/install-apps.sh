#!/usr/bin/env bash
# Optional apps are best effort; never disable the working remote connection.
set -Eeuo pipefail
distro="$WFS_DISTRO"
bundle="$WFS_APPS"
case "$bundle" in none) echo "No optional apps requested."; exit 0;; developer|office|media|all) ;; *) exit 2;; esac
echo "[WFS Linux] Installing optional bundle $bundle on $distro."
docker exec -u 0 wfs-linux-webtop /bin/sh -s -- "$distro" "$bundle" <<'IN_CONTAINER'
set -eu
distro="$1"
bundle="$2"
common="git curl wget"
case "$distro" in
  debian|ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    install() { apt-get install -y -qq --no-install-recommends "$@"; }
    developer="git curl wget python3 python3-pip nodejs npm vim"
    office="libreoffice"
    media="gimp vlc"
    ;;
  fedora)
    install() { dnf -y install "$@"; }
    developer="git curl wget python3 python3-pip nodejs npm vim"
    office="libreoffice"
    media="gimp vlc"
    ;;
  arch)
    pacman -Syu --noconfirm
    install() { pacman -S --needed --noconfirm "$@"; }
    developer="git curl wget python python-pip nodejs npm vim"
    office="libreoffice-fresh"
    media="gimp vlc"
    ;;
  alpine)
    apk update
    install() { apk add --no-cache "$@"; }
    developer="git curl wget python3 py3-pip nodejs npm vim"
    office="libreoffice"
    media="gimp vlc"
    ;;
  *) echo "Unsupported distro" >&2; exit 2 ;;
esac
# Only trusted packages from the distribution package manager are installed.
# shellcheck disable=SC2086
case "$bundle" in
  developer) install $developer ;;
  office) install $office ;;
  media) install $media ;;
  all)
    install $developer
    install $office
    install $media
    ;;
esac
echo "Optional app bundle installed inside temporary container."
IN_CONTAINER
echo "[WFS Linux] Optional packages completed. Packages do not survive a new GitHub runner."
