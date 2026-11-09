#!/usr/bin/env bash
# Independently attempt user-selected Linux apps; keep a working desktop alive.
set -u
distro="$WFS_DISTRO"
status_file="$RUNNER_TEMP/wfs-linux/apps-status.tsv"
mkdir -p "$(dirname "$status_file")"
: > "$status_file"
say() { printf '[WFS Linux Apps] %s\n' "$*"; }
record() { printf '%s\t%s\n' "$1" "$2" >> "$status_file"; say "$1: $2"; }
pkg() {
  case "$distro" in
    debian|ubuntu) docker exec -u 0 wfs-linux-webtop /bin/sh -c "DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $*" ;;
    fedora) docker exec -u 0 wfs-linux-webtop /bin/sh -c "dnf install -y $*" ;;
    arch) docker exec -u 0 wfs-linux-webtop /bin/sh -c "pacman -Sy --needed --noconfirm $*" ;;
    alpine) docker exec -u 0 wfs-linux-webtop /bin/sh -c "apk add --no-cache $*" ;;
    *) return 1 ;;
  esac
}
install_pkg() {
  local title="$1" packages="$2"
  if pkg "$packages"; then record "$title" "INSTALLED (distro package manager)"
  else record "$title" "FAILED (package/dependency issue)"; fi
}
install_vscode() {
  if [ "$distro" = debian ] || [ "$distro" = ubuntu ]; then
    if docker exec -i -u 0 wfs-linux-webtop /bin/sh <<'VSCODE'
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
printf '%s\n' 'Types: deb' 'URIs: https://packages.microsoft.com/repos/code' \
  'Suites: stable' 'Components: main' 'Architectures: amd64' \
  'Signed-By: /usr/share/keyrings/microsoft.gpg' > /etc/apt/sources.list.d/vscode.sources
apt-get update -qq
apt-get install -y -qq --no-install-recommends code
command -v code >/dev/null
VSCODE
    then record "VS Code" "INSTALLED (official Microsoft APT repository)"
    else record "VS Code" "FAILED (APT repository/dependencies)"
    fi
  else
    record "VS Code" "MANUAL (check official Linux release for selected distro)"
  fi
}
node_ready=no
ensure_node() {
  [ "$node_ready" = yes ] && return 0
  # NodeSource Node.js 22 ships npm with nodejs, so NEVER install Debian/Ubuntu
  # apt package npm separately; it conflicts with NodeSource (run #42657742380).
  if [ "$distro" = debian ] || [ "$distro" = ubuntu ]; then
    if ! docker exec -u 0 wfs-linux-webtop /bin/sh -c 'command -v node >/dev/null && command -v npm >/dev/null'; then
      docker exec -u 0 wfs-linux-webtop /bin/sh -c \
        'DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall nodejs' || return 1
    fi
  else
    docker exec -u 0 wfs-linux-webtop /bin/sh -c 'command -v node >/dev/null && command -v npm >/dev/null' ||
      pkg "nodejs npm" || return 1
  fi
  docker exec -u 0 wfs-linux-webtop /bin/sh -c \
    'command -v node >/dev/null && command -v npm >/dev/null && node -e "process.exit(parseInt(process.versions.node,10)>=20?0:1)" && npm --version >/dev/null' || return 1
  node_ready=yes
  say "Node runtime ready: $(docker exec -u 0 wfs-linux-webtop node --version)"
  return 0
}
install_npm() {
  local title="$1" package="$2" binary="$3"
  if ! ensure_node; then record "$title" "FAILED (Node >=20/npm not available)"; return 0; fi
  if timeout 210 docker exec -u 0 wfs-linux-webtop npm install -g --no-audit --no-fund "$package" &&
     docker exec -u 0 wfs-linux-webtop /bin/sh -c "command -v $binary >/dev/null"; then
    record "$title" "INSTALLED (npm package $package, CLI $binary verified)"
  else
    record "$title" "FAILED (npm install or CLI verification)"
  fi
}
case "$WFS_APPS" in
  developer|all)
    case "$distro" in arch) p="git curl wget python python-pip nodejs npm vim";; alpine) p="git curl wget python3 py3-pip nodejs npm vim";; *) p="git curl wget python3 python3-pip nodejs npm vim";; esac
    install_pkg "Developer bundle" "$p" ;;
esac
case "$WFS_APPS" in office|all)
  case "$distro" in arch) p="libreoffice-fresh";; *) p="libreoffice";; esac
  install_pkg "Office bundle" "$p" ;;
esac
case "$WFS_APPS" in media|all) install_pkg "Media bundle" "gimp vlc" ;; esac
case "$WFS_IDE" in vscode|both) install_vscode ;; esac
case "$WFS_IDE" in antigravity|both)
  record "Google Antigravity IDE" "MANUAL (official Linux GUI download; unattended package not verified)" ;;
esac
case "$WFS_EDITOR" in shotcut|both) install_pkg "Shotcut" "shotcut" ;; esac
case "$WFS_EDITOR" in capcut|both)
  record "CapCut" "UNSUPPORTED as native Linux executable (Windows installer)" ;;
esac
case "$WFS_METATRADER" in mt4|both)
  record "MetaTrader 4" "MANUAL (Wine/Windows terminal; no native Linux package)" ;;
esac
case "$WFS_METATRADER" in mt5|both)
  record "MetaTrader 5" "MANUAL (Wine/broker configuration required)" ;;
esac
case "$WFS_ROUTER" in 9router|both) install_npm "9Router" "9router" "9router" ;; esac
case "$WFS_ROUTER" in omniroute|both) install_npm "OmniRoute" "omniroute" "omniroute" ;; esac
case "$WFS_CODING_AGENT" in codex|both) install_npm "Codex CLI" "@openai/codex" "codex" ;; esac
case "$WFS_CODING_AGENT" in claude|both) install_npm "Claude Code" "@anthropic-ai/claude-code" "claude" ;; esac
case "$WFS_AI_AGENT" in hermes|both|all)
  record "Hermes Agent" "MANUAL (official Linux setup/authentication required)" ;;
esac
case "$WFS_AI_AGENT" in openclaw|both|all)
  install_npm "OpenClaw" "openclaw" "openclaw" ;;
esac
case "$WFS_AI_AGENT" in opencode|all)
  install_npm "OpenCode" "opencode-ai" "opencode" ;;
esac
say "All selections accounted for. App-status table is included in Actions Summary."
exit 0
