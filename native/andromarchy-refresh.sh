#!/bin/bash
# Brings the Linux side of an installed Andromarchy up to date with this repository, without reinstalling the app or
# downloading the system image again. Run it in a terminal on the tablet:
#   curl -fsSL https://raw.githubusercontent.com/cylim/andromarchy/main/native/andromarchy-refresh.sh | bash
# or, from a copy of the repository: bash native/andromarchy-refresh.sh /path/to/andromarchy
# It installs again what build-inside.sh and install-omarchy-android.sh put in the image and that changed since:
# the compatibility library, the on-screen keyboard's scripts, Omarchy's package repository and update fixes.
# Idempotent. What lives in the app itself (hardware keyboard detection...) needs the new APK.
set -euo pipefail
SRC=${1:-}
if [ -z "$SRC" ]; then
  SRC=$(mktemp -d)
  trap 'rm -rf "$SRC"' EXIT
  curl -fsSL "https://github.com/${ANDROMARCHY_REPO:-cylim/andromarchy}/archive/${ANDROMARCHY_REF:-main}.tar.gz" |
    tar -xz -C "$SRC" --strip-components=1
fi
[ -f "$SRC/native/android-compat.c" ] || { echo "not an Andromarchy source tree: $SRC" >&2; exit 1; }
[ -d /opt/lotfix ] || { echo "run this inside Andromarchy, on the tablet" >&2; exit 1; }

echo "Compatibility library"
# Every running program has the current one mapped: build beside it, then rename over it (new programs get the new one).
gcc -O2 -shared -fPIC -o /opt/lotfix/.android-compat.so.new "$SRC"/native/android-compat.c "$SRC"/native/go-syscalls.c \
  "$SRC"/native/android-ifaddrs.c -ldl
LD_PRELOAD="$FAKECHROOT_BASE/opt/lotfix/.android-compat.so.new:${LD_PRELOAD#*:}" /usr/bin/true ||
  { echo "the new library does not load; the current one stays" >&2; rm -f /opt/lotfix/.android-compat.so.new; exit 1; }
cp -p /opt/lotfix/android-compat.so /opt/lotfix/android-compat.so.prev
mv /opt/lotfix/.android-compat.so.new /opt/lotfix/android-compat.so
touch /opt/lotfix/firefox-sandbox # Firefox's sandbox can run with this library; an app that knows the mark leaves it on

echo "On-screen keyboard"
SQ=$SRC/omarchy/squeekboard
install -m755 "$SQ"/squeekboard "$SQ"/squeekboard-toggle "$SQ"/squeekboard-theme "$SQ"/squeekboard-next-layout \
  "$SQ"/squeekboard-session /usr/local/bin/
cp "$SQ"/plugin/* ~/.config/omarchy/plugins/andromarchy.squeekboard/
squeekboard-toggle apply || true

echo "Services without the caller's open files (systemctl, systemd-run stand-ins)"
bash "$SRC"/native/install-systemctl.sh >/dev/null
install -m 755 "$SRC"/omarchy/systemd-run-shim.sh /usr/local/bin/systemd-run
install -m 755 "$SRC"/omarchy/uwsm-app-shim.sh /usr/local/bin/uwsm-app

echo "Omarchy: package repository, update fixes"
install -Dm 755 "$SRC"/omarchy/omarchy-update-dev-android.sh /usr/local/share/andromarchy/omarchy-update-dev
install -m 755 "$SRC"/omarchy/omarchy-install-ai-t3-code-android.sh /usr/local/share/andromarchy/omarchy-install-ai-t3-code
install -m 755 "$SRC"/omarchy/omarchy-android-patches.sh /usr/local/bin/omarchy-android-patches
install -m 755 "$SRC"/omarchy/andromarchy-omarchy-repo.sh /usr/local/bin/andromarchy-omarchy-repo
omarchy-android-patches
sudo andromarchy-omarchy-repo
# Omarchy itself on the release this project follows (the downloaded image may hold a development snapshot).
OMARCHY_PATH=/usr/share/omarchy /usr/share/omarchy/bin/omarchy-update-dev
echo "Done. Update everything with: omarchy update"
