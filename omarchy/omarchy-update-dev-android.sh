#!/bin/bash
# Andromarchy's omarchy-update-dev (put in place of Omarchy's by omarchy-android-patches): brings Omarchy itself up
# to date during "omarchy update".
# Omarchy here is a git checkout in /usr/share/omarchy, not the omarchy package (which depends on a boot loader, a
# login manager and NetworkManager), and Omarchy's own omarchy-update-dev skips that path as "installed by pacman":
# updates never touched Omarchy.
# Follows Omarchy's releases: the newest vX.Y.Z tag. They go with the stable package channel pacman uses here
# (andromarchy-omarchy-repo); the development branch (quattro) expects the edge channel's packages (its migrations
# install some that stable does not have) and a newer Hyprland than ours. Another branch or tag: its name in
# /etc/andromarchy/omarchy-ref.
set -euo pipefail
O=${OMARCHY_PATH:-/usr/share/omarchy}
ref=$(cat /etc/andromarchy/omarchy-ref 2>/dev/null || true)
if [[ -z $ref ]]; then
  ref=$(git -C "$O" ls-remote --tags --refs origin 'v*' | sed -n 's|.*refs/tags/\(v[0-9][0-9.]*\)$|\1|p' | sort -V | tail -1)
  [[ -n $ref ]] || { echo "Could not read Omarchy's releases" >&2; exit 1; }
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
new=$(git -C "$O" rev-parse FETCH_HEAD)
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
