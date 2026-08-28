#!/usr/bin/env bash
# Drives the manual takeover this arbiter-less pair requires.
#
# With two failover members and no arbiter, a member that loses its partner cannot
# distinguish a dead partner from a broken network, so it will never promote itself.
# Promotion is an operator decision - that decision is what this script performs.
#
#   1. stop member A (simulating the loss of the primary)
#   2. call BecomePrimary() on member B
#
# Danger, and the reason this is a separate script rather than part of verify.sh: if
# member A is still running and serving clients, promoting member B produces two
# primaries and divergent data. The script refuses to promote while member A is
# reachable unless you pass --force.
#
# Usage:  ./takeover.sh          stop member A, then promote member B
#         ./takeover.sh --force  promote member B without stopping member A
set -euo pipefail
cd "$(dirname "$0")"
. ../../common/setup-lib.sh

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

need_running training-mirror-b

if [ "$FORCE" -eq 0 ]; then
    echo "Stopping training-mirror-a..."
    docker stop training-mirror-a >/dev/null
    echo "Member A stopped."
elif [ "$(docker inspect -f '{{.State.Running}}' training-mirror-a 2>/dev/null)" = "true" ]; then
    echo "WARNING: member A is still running. Promoting member B now creates two"
    echo "         primaries and the two copies will diverge. Continuing (--force)."
fi

echo "Promoting training-mirror-b..."
output=$(os training-mirror-b <<'EOF'
set sc=##class(SYS.Mirror).BecomePrimary() write "become-primary=",$system.Status.IsOK(sc),!
write:'$system.Status.IsOK(sc) "  ",$system.Status.GetErrorText(sc),!
halt
EOF
)

echo "$output" | grep -v '^Node:'
check_steps "$output" || { echo "Takeover failed." >&2; exit 1; }

echo
echo "Member B is now the primary. Confirm with ./verify.sh, and in the portal on"
echo "http://localhost:63774/csp/sys/UtilHome.csp - the banner shows the new role."
echo
echo "To bring member A back as the backup:  docker start training-mirror-a"
