#!/bin/bash
# Prove that the split is real: code executes on one instance, its data is stored
# on the other.
#
# 1. The TRAINING namespace on the code instance must map its routines locally and
#    its globals to a remote (ECP) database.
# 2. A global written by code running on the code instance must become visible on
#    the data instance, which only has a local database - it is not mapping
#    anything from anywhere.
#
# Works both after ./01-data-server.sh + ./02-code-server.sh and after doing the
# same steps by hand in the portal.
set -euo pipefail

cd "$(dirname "$0")"
. ../../common/setup-lib.sh

CODE_CONTAINER=${CODE_CONTAINER:-training-ecp-code}
DATA_CONTAINER=${DATA_CONTAINER:-training-ecp-data}

need_running "$CODE_CONTAINER"
need_running "$DATA_CONTAINER"

echo "== 1. Namespace mapping on the code instance =="

mapping=$(os "$CODE_CONTAINER" <<'OBJECTSCRIPT'
write "routines-destination=",##class(%SYS.Namespace).GetRoutineDest("TRAINING"),!
write "globals-destination=",##class(%SYS.Namespace).GetGlobalDest("TRAINING"),!
halt
OBJECTSCRIPT
)

routines=$(echo "$mapping" | sed -n 's/^routines-destination=//p')
globals=$(echo "$mapping" | sed -n 's/^globals-destination=//p')
echo "  routines: $routines"
echo "  globals:  $globals"

# A remote destination is reported as "<ecp server>^<directory>"; a local one has
# no server name in front of the caret.
if ! echo "$globals" | grep -q '^[A-Za-z0-9]\+\^'; then
    echo
    echo "NOT WIRED YET: the TRAINING globals database is still local."
    echo "Do the exercise (../EXERCISE.md), or run ./01-data-server.sh and ./02-code-server.sh."
    exit 1
fi
if echo "$routines" | grep -q '^[A-Za-z0-9]\+\^'; then
    echo
    echo "WRONG SPLIT: the routines database is remote too."
    echo "The point of this stack is that the code stays local and only the data moves."
    exit 1
fi

echo "== 2. Data written on the code instance, read on the data instance =="

marker="code-instance-$(date +%s)"
os "$CODE_CONTAINER" >/dev/null <<OBJECTSCRIPT
zn "TRAINING" set ^EcpProof("marker")="$marker",^EcpProof("host")=\$system.INetInfo.LocalHostName()
halt
OBJECTSCRIPT
echo "  wrote ^EcpProof(\"marker\")=\"$marker\" on the code instance"

# ECP does not push every write to the data server immediately - modified blocks
# sit in the client's cache until they are flushed. A trainee reading the data
# instance a second later will see nothing yet, which looks like a broken setup
# but is normal, so poll instead of checking once.
echo -n "  waiting for the ECP write to reach the data instance"
found=""
for _ in $(seq 1 20); do
    seen=$(os "$DATA_CONTAINER" <<'OBJECTSCRIPT'
zn "DATA" write "marker=",$get(^EcpProof("marker")),!
halt
OBJECTSCRIPT
)
    value=$(echo "$seen" | sed -n 's/^marker=//p')
    if [ "$value" = "$marker" ]; then found=yes; break; fi
    echo -n "."
    sleep 2
done
echo

if [ -z "$found" ]; then
    echo "FAILED: the global never appeared on the data instance." >&2
    echo "        Check that %Service_ECP is enabled there and that the ECP" >&2
    echo "        connection is Normal in the portal on the code instance." >&2
    exit 1
fi

written_by=$(os "$DATA_CONTAINER" <<'OBJECTSCRIPT'
zn "DATA" write "host=",$get(^EcpProof("host")),!
halt
OBJECTSCRIPT
)
echo "  the data instance sees it, written by host: $(echo "$written_by" | sed -n 's/^host=//p')"
echo
echo "OK - code runs on $CODE_CONTAINER, its data is stored on $DATA_CONTAINER."
