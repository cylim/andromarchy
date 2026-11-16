#!/bin/bash
# /usr/local/bin/systemd-run for Android/Andromarchy. No systemd: xdg-terminal-exec and omarchy-launch-browser start
# apps with "systemd-run --user [--scope]", which fails without a running systemd ("Failed to connect to user scope
# bus"): the config editor and other TUI apps opened and died. Run the command directly: in the foreground with
# --scope, detached otherwise (like a unit).
scope=0
while [ $# -gt 0 ]; do
  case $1 in
    --scope) scope=1; shift ;;
    --*=*) shift ;;
    -u|-p|-E|-M|--unit|--slice|--property|--description|--setenv|--working-directory|--machine|--uid|--gid|--nice) shift 2 ;;
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done
[ $scope = 1 ] && exec "$@"
# Detached, like a unit: without the caller's descriptors beyond 0-2, as systemd starts it. An app started this way
# during "omarchy update" kept the update's lock file, and later updates stopped with "already running".
# (In the forked subshell, right before the exec: the runtime's own descriptors are only closed in the child.)
(
  for fd in /proc/self/fd/*; do
    fd=${fd##*/}
    case $fd in 0 | 1 | 2 | *[!0-9]*) ;; *) eval "exec $fd>&-" 2>/dev/null ;; esac
  done
  exec setsid "$@"
) >/dev/null 2>&1 </dev/null &
