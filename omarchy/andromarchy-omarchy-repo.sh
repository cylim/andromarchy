#!/bin/bash
# /usr/local/bin/andromarchy-omarchy-repo: Omarchy's stable channel for aarch64 in pacman: its package repository
# with its signing key, and its mirror of Arch Linux ARM. Run as root (sudo) by install-omarchy-android.sh and
# andromarchy-refresh. Idempotent.
# "omarchy update" needs it (omarchy-keyring), and Omarchy's Install menus take their packages from it (T3 Code,
# Claude Code, Brave...). First in the list like on every Omarchy: its Quickshell is the one Omarchy's shell is
# written for. Our Mesa, aquamarine and Hyprland stay out of its reach (IgnorePkg, andromarchy-protect).
set -euo pipefail
C=/etc/pacman.conf
KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571

if ! grep -q '^\[omarchy\]' $C; then
  cp -p $C $C.before-omarchy-repo
  sed -i '0,/^\[core\]/s//[omarchy]\nServer = https:\/\/pkgs.omarchy.org\/stable\/$arch\n\n[core]/' $C
fi
# Arch Linux ARM from Omarchy's stable mirror, like Omarchy's own aarch64 setup (default/pacman/aarch64): a snapshot
# that moves when Omarchy releases, with the Hyprland 0.56 / aquamarine 0.15 our builds are made for. The rolling
# mirror left "pacman -Syu" unresolvable for days at a time (hyprtoolkit wanting aquamarine 0.16, which we hold
# back; packages rebuilt for OpenSSL 4 before it reached every mirror). The rolling mirror is not kept as a
# fallback: one database from each (after a failed download) is a mix that cannot be installed.
M=/etc/pacman.d/mirrorlist
if ! grep -q '^Server = https://arm-stable-mirror.omarchy.org/' $M; then
  cp -p $M $M.before-omarchy-repo
  { echo '# Andromarchy: Omarchy'"'"'s stable mirror of Arch Linux ARM (andromarchy-omarchy-repo). Former servers:'
    echo 'Server = https://arm-stable-mirror.omarchy.org/$arch/$repo'
    sed -n 's/^Server = /#Server = /p' $M.before-omarchy-repo; } > $M
fi
# Downloads by curl, which tries again: over HTTPS (these servers; Arch Linux ARM's were plain HTTP), downloads made
# as fake root fail now and then ("ssl/tls alert bad record mac"): pacman's own downloader about one time in three,
# curl started by pacman about one in seven, curl outside sudo never. Packages are still verified by pacman.
# ponytail: something under the fake root (libfakeroot's link to faked?) disturbs the TLS connection; find it, then
# pacman's own parallel downloader can come back
X='XferCommand = /usr/bin/curl -fL -C - --retry 6 --retry-all-errors --retry-delay 1 --progress-bar -o %o %u'
if grep -q '^XferCommand = /usr/bin/curl' $C; then
  sed -i "s|^XferCommand = /usr/bin/curl.*|$X|" $C
else
  sed -i "/^\\[options\\]/a $X" $C
fi
# (pacman runs it as DownloadUser, an account it cannot switch to here: "switching to sandbox user 'alpm' failed")
sed -i 's/^DownloadUser/#DownloadUser/' $C
if ! pacman-key --list-keys $KEY >/dev/null 2>&1; then
  pacman-key --recv-keys $KEY --keyserver keys.openpgp.org
  pacman-key --lsign-key $KEY
fi
pacman -Syy --noconfirm
# pacman-contrib: paccache, which "omarchy update" prunes the package cache with.
pacman -S --noconfirm --needed omarchy-keyring pacman-contrib
