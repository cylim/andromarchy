#!/bin/bash
# Installs docker-systemctl-replacement (gdraheim, EUPL-1.2) as systemctl/journalctl in /usr/local/bin, ahead of
# systemd's own (which needs a running systemd). It reads the real .service files: start/stop/enable, Restart=,
# "systemctl --user default" for enabled units. Run inside the rootfs as root (build), or with DEST=<rootfs>.
set -euo pipefail
V=v1.7.1097
URL=https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/$V/files/docker
SUM_SYSTEMCTL=5f5a47f321c7a8881dfd01f774106dc4012d664bee238eada86a7112674fea93
SUM_JOURNALCTL=16a52fe484d7c0fca464c82a56de58980440362942482c0d1fbc424e69f8f833
D=${DEST:-}/usr/local/bin
X=${DEST:-}/usr/local/libexec
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

curl -fsSL -o "$T/systemctl" "$URL/systemctl3.py"
curl -fsSL -o "$T/journalctl" "$URL/journalctl3.py"
echo "$SUM_SYSTEMCTL  $T/systemctl" | sha256sum -c --quiet
echo "$SUM_JOURNALCTL  $T/journalctl" | sha256sum -c --quiet

# Android denies listing some /sys dirs (power_supply...): daemon-reload crashed on a ConditionDirectoryNotEmpty.
# Treat an unreadable directory as empty.
grep -q '                        elif not os.listdir(filepath):' "$T/systemctl"
sed -i 's/^                        elif not os.listdir(filepath):$/                        elif not os.access(filepath, os.R_OK) or not os.listdir(filepath):/' "$T/systemctl"

# Without RestartSec=, the default 0.1 is passed as "0.1", which time_to_seconds() does not parse: restarts were
# scheduled after the 200 s maximum instead of systemd's 100 ms.
grep -q 'delay = conf.get(section, "RestartSec", default or strE(DefaultRestartSec))' "$T/systemctl"
sed -i 's/delay = conf.get(section, "RestartSec", default or strE(DefaultRestartSec))/delay = conf.get(section, "RestartSec", default or "100ms")/' "$T/systemctl"

# Services start with only stdin/stdout/stderr, as under systemd: every other descriptor the caller had open (fd 3 and
# up) is dropped when the service's program starts. They were inherited: Superwhisper, started by an Omarchy
# migration during "omarchy update", kept the update's lock file open, and every later update stopped with
# "An Omarchy update is already running". Marked close-on-exec rather than closed: the stand-in's own files (journal
# log...) and the preloaded runtime's keep working until the exec.
python3 - "$T/systemctl" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = """        self.dup2_journal_log(conf)
        cmd_args: List[Union[str, bytes]] = []
"""
assert s.count(anchor) == 1, "execve_from changed upstream"
s = s.replace(anchor, """        self.dup2_journal_log(conf)
        drop_inherited_fds()
        cmd_args: List[Union[str, bytes]] = []
""")
helper = """def drop_inherited_fds() -> None:
    \"\"\" Andromarchy: like systemd, a service gets no descriptor of its caller beyond 0-2 (close-on-exec) \"\"\"
    try:
        fds = [int(fd) for fd in os.listdir("/proc/self/fd")]
    except (OSError, ValueError):
        fds = list(range(3, 1024))
    for fd in fds:
        if fd > 2:
            try:
                os.set_inheritable(fd, False)
            except OSError:
                pass

def exec_path(cmd: str)"""
assert s.count("def exec_path(cmd: str)") == 1
s = s.replace("def exec_path(cmd: str)", helper, 1)
open(p, "w").write(s)
PY

mkdir -p "$D" "$X"
# systemctl itself is a wrapper (native/systemctl-wrapper.sh): power verbs go to the app.
install -m 755 "$T/systemctl" "$X/systemctl"
install -m 755 "$T/journalctl" "$D/"
install -m 755 "$(dirname "$0")/systemctl-wrapper.sh" "$D/systemctl"
echo "systemctl replacement $V installed in $D"
