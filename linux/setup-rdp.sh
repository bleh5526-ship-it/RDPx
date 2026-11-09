#!/usr/bin/env bash
# Optional native xrdp in selected distro; separate desktop from browser.
set -Eeuo pipefail
die() { echo "::error::$*" >&2; exit 1; }
info() { echo "[WFS Linux xrdp] $*"; }
case "$WFS_REMOTE" in
  novnc) info "Browser only; no xrdp required."; exit 0 ;;
  rdp|both) ;;
  *) die "Unsupported remote mode." ;;
esac
case "$WFS_DISTRO" in
  debian|ubuntu|fedora|alpine) ;;
  arch) die "Arch needs AUR packages for xrdp. Choose Debian/Ubuntu/Fedora/Alpine or novnc." ;;
  *) die "Unsupported Linux distro for native RDP." ;;
esac
docker inspect wfs-linux-webtop >/dev/null || die "Desktop container missing."
info "Setting up xrdp/Xorg Xfce on $WFS_DISTRO, account $WFS_RDP_USERNAME."
docker exec -i -u 0 wfs-linux-webtop /bin/sh -s -- "$WFS_DISTRO" "$WFS_RDP_USERNAME" <<'IN_CONTAINER'
set -eu
distro="$1"
username="$2"
export DEBIAN_FRONTEND=noninteractive
case "$distro" in
  debian|ubuntu)
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
      xrdp xorgxrdp xserver-xorg-core xfce4-session xfce4-panel xfce4-settings \
      dbus-x11 passwd pamtester
    ;;
  fedora)
    dnf install -y xrdp xorgxrdp xorg-x11-server-Xorg \
      xfce4-session xfce4-panel xfce4-settings dbus-x11 shadow-utils pamtester
    ;;
  alpine)
    apk add --no-cache xrdp xorgxrdp xorg-server \
      xfce4-session xfce4-panel xfce4-settings dbus-x11 shadow pamtester
    ;;
esac
command -v xrdp >/dev/null 2>&1
command -v xrdp-sesman >/dev/null 2>&1
command -v startxfce4 >/dev/null 2>&1
password="$(cat /run/secrets/rdp_password)"
test -n "$password"
if ! id "$username" >/dev/null 2>&1; then
  useradd -m -s /bin/sh "$username"
fi
getent passwd "$username" >/dev/null || { echo "xrdp account missing from NSS"; exit 24; }
id "$username" >/dev/null || { echo "xrdp user lookup failed"; exit 25; }
printf '%s:%s\n' "$username" "$password" | chpasswd
unset password
# Validate xrdp PAM authentication using the secret file, not just TCP.
# Never place the password in process arguments or the job log.
test -f /etc/pam.d/xrdp-sesman || { echo "xrdp PAM configuration missing" >&2; exit 26; }
command -v pamtester >/dev/null || { echo "pamtester missing" >&2; exit 27; }
if ! { cat /run/secrets/rdp_password; printf '\n'; } | pamtester xrdp-sesman "$username" authenticate acct_mgmt >/dev/null; then
  echo "xrdp PAM authentication/account check failed; not publishing RDP." >&2
  exit 28
fi
echo "[WFS Linux xrdp] PASS: Unix account and xrdp-sesman PAM login verified."
home="$(getent passwd "$username" | cut -d: -f6)"
test -n "$home"
test -d "$home" || { echo "xrdp user home missing" >&2; exit 29; }
cat > "$home/.xsession" <<'XSESSION'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec dbus-launch --exit-with-session startxfce4
XSESSION
chown "$username:$username" "$home/.xsession"
chmod 700 "$home/.xsession"
mkdir -p /run/xrdp /var/log
if [ -f /etc/X11/Xwrapper.config ]; then
  printf '%s\n' 'allowed_users=anybody' 'needs_root_rights=auto' > /etc/X11/Xwrapper.config
fi
if command -v dbus-daemon >/dev/null 2>&1 && [ ! -S /run/dbus/system_bus_socket ]; then
  mkdir -p /run/dbus
  dbus-daemon --system --fork >/dev/null 2>&1 || true
fi
xrdp-sesman
xrdp
IN_CONTAINER
info "Probing xrdp via 127.0.0.1:13389 (TPKT / X.224)."
python3 - <<'PY'
import socket, time
# TPKT + X.224 CR + RDP negotiation req with SSL protocol.
hello = bytes.fromhex("030000130ee000000000000100080003000000")
for attempt in range(25):
    try:
        with socket.create_connection(("127.0.0.1", 13389), timeout=3) as s:
            s.settimeout(5)
            s.sendall(hello)
            data = s.recv(64)
        if len(data) >= 11 and data[:2] == b"\x03\x00":
            print("PASS: xrdp X.224 response over local loopback.")
            break
    except OSError:
        pass
    time.sleep(2)
else:
    raise SystemExit("xrdp did not respond via loopback. Check docker exec xrdp/sesman logs.")
PY
echo "WFS_RDP_READY=1" >> "$GITHUB_ENV"
info "RDP backend verified: Linux account, PAM authentication, home, Xfce session script, TCP protocol. GUI login from your client still needs acceptance testing."
