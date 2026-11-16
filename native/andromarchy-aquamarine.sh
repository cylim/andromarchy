#!/bin/bash
# Rebuilds aquamarine (the compositor's backend, with our Andromarchy backend) inside an installed system when its
# patches changed, and puts the library in place. Usage: andromarchy-aquamarine.sh <patches/aquamarine dir>
# The image carries a prebuilt one (build/build-hyprland.sh); a change to the patches reaches installed systems
# through here (native/andromarchy-refresh.sh). Hyprland loads the new library at the next start of the app.
set -euo pipefail
P=$(cd "${1:?patches/aquamarine directory}" && pwd)
TAG=v0.15.1 # the version our Hyprland is built against (build/build-hyprland.sh)
LIB=/usr/lib/libaquamarine.so.0.15.1
STAMP=/opt/lotfix/aquamarine-patches.sha256
want=$(cat "$P"/*.patch | sha256sum | cut -d' ' -f1)
[ "$(cat $STAMP 2>/dev/null)" = "$want" ] && [ -f $LIB ] && { echo "aquamarine is up to date"; exit 0; }

sudo pacman -S --noconfirm --needed git cmake ninja gcc pkgconf hyprwayland-scanner wayland-protocols hwdata \
  libdisplay-info libinput seatd pixman
W=$(mktemp -d /var/tmp/aquamarine.XXXXXX)
trap 'rm -rf "$W"' EXIT
git -c advice.detachedHead=false clone -q --depth 1 -b $TAG https://github.com/hyprwm/aquamarine "$W/src"
git -C "$W/src" apply "$P"/*.patch
cmake -S "$W/src" -B "$W/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr >/dev/null
ninja -C "$W/build" >/dev/null
built=$(ls "$W"/build/libaquamarine.so.0.* | grep -v '\.so\.0\.[0-9]*$' | head -1)
built=${built:-$W/build/$(basename $LIB)}
[ -f "$built" ] || { echo "aquamarine did not build" >&2; exit 1; }
# The running Hyprland has the current library mapped: the new one beside it, then renamed over it. Recorded as
# ours, or the next pacman transaction would put the previous one back (andromarchy-protect).
cp -p $LIB $LIB.prev 2>/dev/null || true
install -m 755 "$built" $LIB.new
mv $LIB.new $LIB
andromarchy-protect save
echo "$want" > $STAMP
echo "aquamarine rebuilt: restart Andromarchy to use it"
