#!/bin/bash
# Andromarchy's omarchy-install-ai-t3-code (put in place of Omarchy's by omarchy-android-patches): Install > AI >
# T3 Code in Omarchy's menu.
# Omarchy installs T3 Code's AppImage and reads its command-line tool through "--appimage-mount", which needs FUSE:
# Android gives apps none, and the install stopped on "Could not open .../T3-Code.AppImage". Here T3 Code comes from
# Omarchy's package repository instead (t3code-bin, built for ARM), with the same theme and launch steps.
# omarchy-remove-ai-t3-code removes it as it is (it drops both packages).
set -e
T3CODE_HOME="${T3CODE_HOME:-$HOME/.t3}"

channel=""
launch=1
for arg in "$@"; do
  if [[ $arg == "--no-launch" ]]; then
    launch=0
  else
    channel=$arg
  fi
done
if [[ -z $channel ]]; then
  stable=$(omarchy-i18n t3code.stable)
  nightly=$(omarchy-i18n t3code.nightly)
  choice=$(gum choose --header "$(omarchy-i18n t3code.selectChannel)" "$stable" "$nightly")
  if [[ $choice == "$nightly" ]]; then
    channel="nightly"
  else
    channel="stable"
  fi
fi
if [[ $channel == "nightly" ]]; then
  pkg=t3code-nightly-bin other=t3code-bin
else
  pkg=t3code-bin other=t3code-nightly-bin
fi

echo "Installing T3 Code..."
omarchy-pkg-drop "$other" # the two packages hold the same files
omarchy-pkg-add "$pkg"
# An AppImage left by an earlier try of Omarchy's own installer, and its launcher entry, which hides the package's.
rm -rf "$HOME/.local/share/t3code" "$HOME/.local/share/applications/t3code.desktop"

echo "Matching T3 Code to the current theme..."
mkdir -p "$T3CODE_HOME/userdata"
if [[ ! -f $HOME/.local/state/omarchy/current/theme/t3code.json ]]; then
  omarchy-theme-refresh
fi
omarchy-theme-set-t3code
cli=$(pacman -Qlq "$pkg" | grep -m1 -E '^/usr/bin/t3(-nightly)?$' || true)
[[ -z $cli ]] || "$cli" theme set omarchy --base-dir "$T3CODE_HOME" ||
  echo "The Omarchy theme could not be selected in T3 Code; choose it in its settings."

if ((launch)); then
  echo "Opening T3 Code..."
  desktop=$(pacman -Qlq "$pkg" | sed -n 's|^/usr/share/applications/\(.*\)\.desktop$|\1|p' | head -1)
  setsid uwsm-app -- gtk-launch "${desktop:-t3code}" >/dev/null 2>&1 &
fi

echo ""
echo "T3 Code has been installed. It updates with the system: omarchy update."
