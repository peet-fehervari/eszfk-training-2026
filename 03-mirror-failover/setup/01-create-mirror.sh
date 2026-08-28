#!/usr/bin/env bash
# Step 1 of the scripted equivalent of EXERCISE.md, run on member A.
#
# Creates the mirror set and makes member A its primary:
#   - enable %Service_Mirror (off by default)
#   - create mirror set TRAINMIRROR with MEMBERA as the first failover member
#   - add MIRRORDATA to the mirror
#
# No arbiter and no virtual IP are configured - see the header of
# ../docker-compose.yml for why.
#
# Usage:  ./01-create-mirror.sh
set -euo pipefail
cd "$(dirname "$0")"
. ../../common/setup-lib.sh

CONTAINER=training-mirror-a
MIRROR=TRAINMIRROR
MEMBER=MEMBERA
HOST=mirror-a
AGENT_PORT=2188
DB_DIR=/usr/irissys/mgr/mirrordata/
DB_NAME=MIRRORDATA

need_running "$CONTAINER"

echo "Creating mirror set $MIRROR on $CONTAINER..."

# The heredoc is unquoted so the shell substitutes the settings above. ObjectScript
# indirection is therefore escaped as \$, and one complete command per line.
output=$(os "$CONTAINER" <<EOF
set p("Enabled")=1 set sc=##class(Security.Services).Modify("%Service_Mirror",.p) write "enable-mirror-service=",\$system.Status.IsOK(sc),!
write:'\$system.Status.IsOK(sc) "  ",\$system.Status.GetErrorText(sc),!
set i("ArbiterNode")="",i("VirtualAddress")="",i("UseSSL")=0 set i("ECPAddress")="$HOST",i("MirrorAddress")="$HOST",i("AgentAddress")="$HOST",i("AgentPort")=$AGENT_PORT set sc=##class(SYS.Mirror).CreateNewMirrorSet("$MIRROR","$MEMBER",.i) write "create-mirror-set=",\$system.Status.IsOK(sc),!
write:'\$system.Status.IsOK(sc) "  ",\$system.Status.GetErrorText(sc),!
write "mirror-started=",##class(SYS.Mirror).IsMirrorStarted("$MIRROR"),!
set sc=##class(SYS.Mirror).AddDatabase("$DB_DIR","$DB_NAME",1) write "add-database=",\$system.Status.IsOK(sc),!
write:'\$system.Status.IsOK(sc) "  ",\$system.Status.GetErrorText(sc),!
halt
EOF
)

echo "$output" | grep -v '^Node:'
check_steps "$output" || { echo "Mirror creation incomplete." >&2; exit 1; }

echo
echo "Member A is the primary of $MIRROR. Next: ./02-join-mirror.sh"
