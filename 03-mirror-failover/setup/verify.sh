#!/usr/bin/env bash
# Reports the mirror from both members' point of view.
#
# Read-only: it changes nothing, so it is safe to run at any stage - before the
# mirror exists, half-configured, or after a takeover.
#
# For each member it prints how that member sees itself and its partner, and which
# databases that member has in the mirror. A member's own view is the authoritative
# one for its own role; the two views agreeing is what tells you the mirror is
# healthy.
#
# Usage:  ./verify.sh
set -uo pipefail
cd "$(dirname "$0")"
. ../../common/setup-lib.sh

MIRROR=TRAINMIRROR

report() {
    local container=$1
    echo "=== $container ==="
    if [ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" != "true" ]; then
        echo "  not running"
        echo
        return
    fi

    # GetFailoverMemberStatus(&ThisMember,&OtherMember) returns two $lists:
    # 1=member name, 2=agent address, 3=role, 4=status, 5-6=superserver addresses.
    os "$container" <<EOF | grep -v '^Node:\|^$' | sed 's/^/  /'
write "mirror-started=",##class(SYS.Mirror).IsMirrorStarted("$MIRROR"),!
do ##class(SYS.Mirror).GetFailoverMemberStatus(.t,.o)
write "this-member=",\$listget(t,1)," role=",\$listget(t,3)," status=",\$listget(t,4),!
write "other-member=",\$listget(o,1)," role=",\$listget(o,3)," status=",\$listget(o,4),!
set r=##class(%ResultSet).%New("Config.Databases:MirrorDatabaseList") do r.Execute("*")
while r.Next() { write "mirrored-db=",r.GetData(1)," set=",r.GetData(2)," dir=",r.GetData(3),! }
halt
EOF
    echo
}

report training-mirror-a
report training-mirror-b

cat <<'TXT'
Expected once the mirror is set up:
  mirror-a  this=MEMBERA role=Primary status=Active   other=MEMBERB role=Backup
  mirror-b  this=MEMBERB role=Backup  status=Active   other=MEMBERA role=Primary

A "mirrored-db=MIRRORDATA" line must appear on BOTH members before data written on
the primary can show up on the backup. If it is missing on member B, see the
"Adding the database on the backup" section of ../README.md.
TXT
