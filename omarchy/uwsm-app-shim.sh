#!/bin/bash
# /usr/local/bin/uwsm-app for Android/Andromarchy. No systemd user session: the app launcher runs
# "uwsm-app -- gtk-launch x.desktop" (uwsm puts apps in a scope). Drop uwsm-app's options and run the command as it is.
while [ $# -gt 0 ]; do
  case $1 in
    -s|-a|-u|-d|-t|-S) shift 2 ;;
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done
# Without the caller's descriptors beyond 0-2, as an app started by systemd: one started during "omarchy update" would
# keep the update's lock file (see systemd-run-shim.sh).
for fd in /proc/self/fd/*; do
  fd=${fd##*/}
  case $fd in 0 | 1 | 2 | *[!0-9]*) ;; *) eval "exec $fd>&-" 2>/dev/null ;; esac
done
exec "$@"
