#!/bin/bash
# Andromarchy's omarchy-update-dev (put in place of Omarchy's by omarchy-android-patches): brings Omarchy itself up
# to date during "omarchy update".
# Omarchy here is a git checkout in /usr/share/omarchy, not the omarchy package (which depends on a boot loader, a
# login manager and NetworkManager), and Omarchy's own omarchy-update-dev skips that path as "installed by pacman":
# updates never touched Omarchy.
# Follows Omarchy 4.5: the newest v4.5.x tag. That release goes with the stable package channel pacman uses here
# (andromarchy-omarchy-repo) and with our Hyprland 0.56; the development branch (quattro) expects the edge channel's
# packages (its migrations install some that stable does not have) and a newer Hyprland. A later series, a branch or
# a tag: its name in /etc/andromarchy/omarchy-ref (v4.6 follows v4.6.x; quattro, v4.5.0... are taken as they are).
set -euo pipefail
O=${OMARCHY_PATH:-/usr/share/omarchy}
ref=$(cat /etc/andromarchy/omarchy-ref 2>/dev/null || true)
ref=${ref:-v4.5}
if [[ $ref =~ ^v[0-9]+\.[0-9]+$ ]]; then # a series: its newest release
  series=$ref
  ref=$(git -C "$O" ls-remote --tags --refs origin "$series.*" | sed -n 's|.*refs/tags/\(v[0-9][0-9.]*\)$|\1|p' | sort -V | tail -1)
  [[ -n $ref ]] || { echo "Could not read Omarchy's $series releases" >&2; exit 1; }
fi
state=$HOME/.local/state/andromarchy

echo -e "\e[32m\nUpdate Omarchy ($ref)\e[0m"
# Every migration of the installed version counts as run, as after Omarchy's own install: without the marks the first
# update replayed all of them, written for machines installed years ago.
if [[ ! -d $HOME/.local/state/omarchy/migrations ]]; then
  mkdir -p "$HOME/.local/state/omarchy/migrations"
  for m in "$O"/migrations/*.sh; do
    [[ -f $m ]] && touch "$HOME/.local/state/omarchy/migrations/${m##*/}"
  done
fi

old=$(git -C "$O" rev-parse HEAD)
git -C "$O" fetch --quiet --depth 1 origin "$ref" # (a tag or a branch: FETCH_HEAD either way)
new=$(git -C "$O" rev-parse "FETCH_HEAD^{commit}") # (an annotated tag: its commit)
if [[ $new == "$old" ]]; then
  echo "Omarchy is up to date"
else
  mkdir -p "$state"
  echo "$old" > "$state/omarchy-previous" # to go back: git -C /usr/share/omarchy reset --hard <it>, omarchy-android-patches
  # The only local changes are omarchy-android-patches', applied again below.
  git -C "$O" reset --quiet --hard FETCH_HEAD
  git --no-pager -C "$O" log -1 --format='Omarchy is now at %h (%cd)' --date=short
fi
omarchy-android-patches
