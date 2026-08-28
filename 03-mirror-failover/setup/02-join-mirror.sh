#!/usr/bin/env bash
# Step 2 of the scripted equivalent of EXERCISE.md, run on member B.
#
# Joins member B to the mirror as the second failover member, which makes it the
# backup:
#   - enable %Service_Mirror
#   - JoinMirrorAsFailoverMember against member A's ISCAgent
#
# With UseSSL=0 the joining member registers itself with the primary, so no separate
# AddFailoverMember call on member A is needed.
#
# NOT done here - member B's own copy of MIRRORDATA is not added to the mirror. See
# the "Adding the database on the backup" section of ../README.md: that step needs a
# journal point and is left to be worked out on the live pair.
#
# Usage:  ./02-join-mirror.sh
set -euo pipefail
cd "$(dirname "$0")"
. ../../common/setup-lib.sh

CONTAINER=training-mirror-b
MIRROR=TRAINMIRROR
MEMBER=MEMBERB
HOST=mirror-b
PRIMARY_HOST=mirror-a
PRIMARY_INSTANCE=IRIS
PRIMARY_AGENT_PORT=2188
AGENT_PORT=2188

need_running "$CONTAINER"

echo "Joining $CONTAINER to $MIRROR as $MEMBER..."

output=$(os "$CONTAINER" <<EOF
set p("Enabled")=1 set sc=##class(Security.Services).Modify("%Service_Mirror",.p) write "enable-mirror-service=",\$system.Status.IsOK(sc),!
write:'\$system.Status.IsOK(sc) "  ",\$system.Status.GetErrorText(sc),!
set l("ECPAddress")="$HOST",l("MirrorAddress")="$HOST",l("AgentAddress")="$HOST",l("AgentPort")=$AGENT_PORT set sc=##class(SYS.Mirror).JoinMirrorAsFailoverMember("$MIRROR","$MEMBER","$PRIMARY_INSTANCE","$PRIMARY_HOST",$PRIMARY_AGENT_PORT,.l) write "join=",\$system.Status.IsOK(sc),!
write:'\$system.Status.IsOK(sc) "  ",\$system.Status.GetErrorText(sc),!
halt
EOF
)

echo "$output" | grep -v '^Node:'
check_steps "$output" || { echo "Join incomplete." >&2; exit 1; }

echo
echo "Member B joined. Roles settle within a few seconds - check with ./verify.sh"
echo "Note: MIRRORDATA is not yet mirrored on member B (see ../README.md)."
