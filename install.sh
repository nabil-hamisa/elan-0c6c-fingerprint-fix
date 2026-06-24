#!/bin/bash
#
# Enable the Elan ELAN:ARM-M4 fingerprint reader (USB 04f3:0c6c) on Linux.
#
# This sensor is a match-on-chip device not supported by upstream libfprint.
# The community "elanmoc2" fork (gitlab.freedesktop.org/geodic/libfprint) adds
# the protocol; this script also registers our specific USB id 04f3:0c6c, which
# is not in the fork's table by default.
#
# Tested on Kali Linux (rolling, amd64), libfprint 1.94.9 fork build.
#
# Usage:
#   sudo bash install.sh
#
set -euo pipefail

FORK_URL="https://gitlab.freedesktop.org/geodic/libfprint.git"
WORKDIR="${WORKDIR:-$HOME/libfprint-elanmoc2-0c6c}"
PATCH="$(cd "$(dirname "$0")" && pwd)/0001-elanmoc2-add-04f3-0c6c.patch"
DEST=/usr/lib/x86_64-linux-gnu

[ "$(id -u)" = 0 ] || { echo "ERROR: run as root:  sudo bash install.sh"; exit 1; }
[ -f "$PATCH" ]    || { echo "ERROR: patch not found next to script: $PATCH"; exit 1; }

# the repo is cloned/built as the invoking user, not root
RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
as_user() { sudo -u "$RUN_USER" "$@"; }

echo "==> 1/7 Install build dependencies"
apt-get install -y \
  git meson ninja-build gcc pkg-config \
  libglib2.0-dev libgusb-dev libnss3-dev libpixman-1-dev \
  libgudev-1.0-dev libsystemd-dev libpolkit-gobject-1-dev

echo "==> 2/7 Clone elanmoc2 fork"
if [ -d "$WORKDIR/.git" ]; then
  as_user git -C "$WORKDIR" fetch --depth 1 origin master
  as_user git -C "$WORKDIR" checkout -f master
  as_user git -C "$WORKDIR" reset --hard origin/master
else
  as_user git clone --depth 1 "$FORK_URL" "$WORKDIR"
fi

echo "==> 3/7 Apply 04f3:0c6c patch"
cd "$WORKDIR"
as_user git apply --verbose "$PATCH" 2>/dev/null \
  || grep -q "0x0c6c" libfprint/drivers/elanmoc2/elanmoc2.c \
  || { echo "ERROR: patch failed and id not present"; exit 1; }

echo "==> 4/7 Build (drivers: elanmoc2, elanmoc, virtual_image)"
as_user rm -rf builddir
as_user meson setup builddir --prefix=/usr \
  -Ddrivers=elanmoc2,elanmoc,virtual_image \
  -Ddoc=false -Dintrospection=false -Dgtk-examples=false
as_user ninja -C builddir

BUILT="$WORKDIR/builddir/libfprint/libfprint-2.so.2.0.0"
[ -f "$BUILT" ] || { echo "ERROR: build produced no lib"; exit 1; }

echo "==> 5/7 Switch fprintd stack to amd64 (the i386 daemon loads the wrong lib)"
systemctl stop fprintd 2>/dev/null || true
pkill -x fprintd 2>/dev/null || true
# NOTE: 'apt-get update' is intentionally skipped; broken third-party repos can
# abort it. Remove this comment / add update if your repos are clean.
apt-get install -y fprintd libfprint-2-2 libpam-fprintd
dpkg -l | awk '/^ii/ && /:i386/ && /fprint/ {print $2}' | xargs -r apt-get purge -y || true

echo "==> 6/7 Install patched lib over the package lib"
rm -f /usr/local/lib/x86_64-linux-gnu/libfprint-2.so* || true   # remove any stale build
install -m0644 "$BUILT" "$DEST/libfprint-2.so.2.0.0"
ln -sf libfprint-2.so.2.0.0 "$DEST/libfprint-2.so.2"
ldconfig
udevadm control --reload || true
udevadm trigger || true
# stop apt from overwriting our patched lib on upgrade
apt-mark hold libfprint-2-2 || true

echo "==> 7/7 Verify the driver claims 04f3:0c6c"
G_MESSAGES_DEBUG=all timeout 8 /usr/libexec/fprintd 2>&1 \
  | grep -iE "0C6C|elanmoc2|No driver found for USB device 04F3" | head || true
pkill -x fprintd 2>/dev/null || true

cat <<EOF

DONE.

Enroll (as your normal user, NOT root):
    fprintd-enroll
Test:
    fprintd-verify
Enable fingerprint for login / sudo:
    sudo pam-auth-update      # tick "Fingerprint authentication"

If an apt upgrade ever breaks the reader, re-run this script. The lib is held
(apt-mark) but a forced reinstall can still clobber it.
EOF
