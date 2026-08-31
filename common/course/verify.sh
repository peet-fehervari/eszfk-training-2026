#!/usr/bin/env bash
# Checks that the course exercises can actually be carried out on an instance.
#
# Works on any instance in any stack, after prepare-instance.sh and, for the checks
# from 3 onwards, install-phonebook.sh have been run on it.
#
# Read-only with one exception, marked below: it starts and stops IRIS to prove the
# "Restart your instance" and emergency-access-mode exercises work. Skip that with
# --no-restart if the instance is in use.
#
# What it checks, and which module needs it:
#   1. instance licensed                       every module
#   2. the six course directories exist, are writable by IRIS, and have the
#      contents they should                    Configuring the System, Applications,
#                                              Journaling, Backup, Encryption
#   3. Phonebook application installed and populated
#                                              Applications and everything after it
#   4. MIS.Simulation present and callable     Backup, Monitoring, Log Review
#   5. Phonebook web pages served through the gateway
#                                              Applications, Authorization
#   6. mail server reachable from IRIS         Monitoring, Automation, Authentication
#   7. OS accounts exist                       Authentication
#   8. ISCAgent listening                      Mirroring
#   9. IRIS stop/start and emergency access mode inside the container
#                                              Backup, Security Installation
#
# Usage:  ./verify.sh [--no-restart] <container> [portal port]
#         ./verify.sh --no-restart training-health 61773
set -uo pipefail
cd "$(dirname "$0")"
. ../setup-lib.sh

DO_RESTART=1
[ "${1:-}" = "--no-restart" ] && { DO_RESTART=0; shift; }
CONTAINER=${1:-${COURSE_CONTAINER:-}}
if [ -z "$CONTAINER" ]; then
    echo "Usage: $0 [--no-restart] <container> [portal port]" >&2
    exit 2
fi
# The portal is on a different host port in every stack, and the check is skipped when
# it is not given rather than guessing wrong and reporting a false failure.
PORTAL_PORT=${2:-${COURSE_PORTAL_PORT:-}}
MAIL_CONTAINER=${MAIL_CONTAINER:-course-mail}
MAIL_UI_PORT=${PORT_MAIL_UI:-61026}

need_running "$CONTAINER"

fails=0
warns=0
ok()   { echo "  OK      $*"; }
bad()  { echo "  FAILED  $*"; fails=$((fails+1)); }
# A warning is something that costs convenience, not an exercise.
warn() { echo "  WARN    $*"; warns=$((warns+1)); }
note() { echo "          $*"; }

echo "== 1. Licence =="
# Captured into a variable first, deliberately. Piping docker logs straight into
# "grep -q" is flaky: grep exits at the first match, docker logs takes SIGPIPE, and
# with pipefail that reads as a failed check on a licensed instance.
startup_log=$(docker logs "$CONTAINER" 2>&1)
if echo "$startup_log" | grep -q "LMF Info.*Licensed for"; then
    ok "$(echo "$startup_log" | grep -o 'Licensed for.*' | tail -1)"
else
    bad "no 'LMF Info: Licensed for N cores' in the log - the instance is unlicensed"
    note "ECP, mirroring and more than 5 connections will not work. Check IRIS_KEY_DIR."
fi

echo "== 2. Course directories =="
# Every one of these is a default that can be overridden; they are checked at the
# defaults because that is what the exercise text names.
iris_uid=$(docker exec "$CONTAINER" id -u)
dirs_out=$(docker exec "$CONTAINER" bash -c '
for d in /Management /databases /backups /journals/jrn /journals/altjrn /InterSystems/training/encryptionkey /irisdev/out; do
    if [ ! -d "$d" ]; then echo "MISSING $d"
    elif [ ! -w "$d" ]; then echo "READONLY $d"
    else echo "WRITABLE $d"; fi
done' 2>&1)
while read -r state dir; do
    case "$state $dir" in
        "WRITABLE "*) ok "$dir writable by uid $iris_uid" ;;
        # /irisdev/out is the one host bind mount, so it carries the host user's
        # ownership instead of the image's. It only exists so ^SystemPerformance and
        # Diagnostic Report HTML can be opened from the host without docker cp - the
        # measuring exercises themselves work either way, writing to the default
        # location inside the container. Hence a warning, not a failure.
        "READONLY /irisdev/out")
            warn "/irisdev/out is not writable by uid $iris_uid"
            note "Reports can still be written elsewhere in the container. To use it:"
            note "    chmod 777 $(pwd)/out        # no sudo needed, you own it" ;;
        # Only exists with the stack's course-overlay.yml, which is optional.
        "MISSING /irisdev/out")
            note "/irisdev/out not mounted - reports stay inside the container"
            note "To get them on the host, start the stack with -f course-overlay.yml" ;;
        "READONLY "*) bad "$dir exists but IRIS cannot write it" ;;
        "MISSING "*)  bad "$dir does not exist" ;;
    esac
done <<< "$dirs_out"

material=$(docker exec "$CONTAINER" bash -c 'ls /Management 2>/dev/null | tr "\n" " "')
case "$material" in
    *PhonebookInstaller.xml*) ok "/Management seeded: $material" ;;
    *) bad "/Management has no PhonebookInstaller.xml (got: ${material:-empty})"
       note "The student files are not in place. Put them in ./material/ - the exact"
       note "list is in PREREQUISITES.md - then re-run ./prepare-instance.sh" ;;
esac

echo "== 3. Phonebook application =="
app=$(os "$CONTAINER" <<'OBJECTSCRIPT'
write "namespace-phonebook=",##class(Config.Namespaces).Exists("PHONEBOOK"),!
write "db-company=",##class(Config.Databases).Exists("COMPANY"),!
write "db-customer=",##class(Config.Databases).Exists("CUSTOMER"),!
write "db-personal=",##class(Config.Databases).Exists("PERSONAL"),!
write "db-pbcode=",##class(Config.Databases).Exists("PBCODE"),!
zn "PHONEBOOK" write "class-company=",##class(%Dictionary.CompiledClass).%ExistsId("Phonebook.Company"),!
zn "PHONEBOOK" write "routine-phonebook=",##class(%Routine).Exists("Phonebook.int"),!
halt
OBJECTSCRIPT
)
if echo "$app" | grep -q '^namespace-phonebook=1'; then
    for line in $(echo "$app" | grep -E '^(namespace|db|class|routine)-'); do
        case "$line" in *=1) ok "$line" ;; *) bad "$line" ;; esac
    done
    # Counted with SQL, not %Count() - %Count() is not a method these classes have.
    counts=$(os "$CONTAINER" <<'OBJECTSCRIPT'
zn "PHONEBOOK" set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Phonebook.Company") do rs.%Next() write "companies=",rs.%GetData(1),!
zn "PHONEBOOK" set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Phonebook.Customer") do rs.%Next() write "customers=",rs.%GetData(1),!
zn "PHONEBOOK" set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Phonebook.Personal") do rs.%Next() write "personals=",rs.%GetData(1),!
halt
OBJECTSCRIPT
)
    echo "$counts" | grep -E '^(companies|customers|personals)=' | while read -r l; do note "$l"; done
    # The global mappings are what the Authorization and ECP modules depend on:
    # ^Phonebook.CustomerD must resolve to the CUSTOMER database, not PHONEBOOK's.
    map=$(os "$CONTAINER" <<'OBJECTSCRIPT'
zn "PHONEBOOK" write "customer-mapped=",$piece(##class(%SYS.Namespace).GetGlobalDest("PHONEBOOK","Phonebook.CustomerD"),"^",2),!
halt
OBJECTSCRIPT
)
    note "$(echo "$map" | sed -n 's/^customer-mapped=/^Phonebook.CustomerD lives in: /p')"
else
    bad "Phonebook is not installed"
    note "Run ./install-phonebook.sh, or do the Applications module by hand."
fi

echo "== 4. MIS.Simulation =="
sim=$(os "$CONTAINER" <<'OBJECTSCRIPT'
zn "PHONEBOOK" write "class-mis-simulation=",##class(%Dictionary.CompiledClass).%ExistsId("MIS.Simulation"),!
zn "%SYS" write "backupdir=",$get(^MIS.Simulation("Backup","backupdir"),"/backups (default)"),!
halt
OBJECTSCRIPT
)
case "$sim" in
    *class-mis-simulation=1*) ok "MIS.Simulation compiled in PHONEBOOK"
        note "$(echo "$sim" | sed -n 's/^backupdir=/backup directory: /p')" ;;
    *) bad "MIS.Simulation is missing - Backup(), Crisis(), StressGlobals() unavailable" ;;
esac

echo "== 5. Phonebook web pages through the gateway =="
# An unauthenticated portal request returns 200 even for pages that do not exist,
# so a 200 proves nothing on its own. What is checked here is that the gateway
# reaches IRIS at all (a gateway that cannot connect returns 500), and that the
# CSP application is really defined in IRIS.
if [ -z "$PORTAL_PORT" ]; then
    note "portal port not given, HTTP check skipped - pass it as the second argument"
else
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${PORTAL_PORT}/csp/sys/UtilHome.csp" 2>/dev/null || echo 000)
    case "$code" in
        200) ok "gateway serves the portal on $PORTAL_PORT (HTTP $code)" ;;
        000) bad "nothing answers on port $PORTAL_PORT" ;;
        *)   bad "gateway returned HTTP $code - it probably cannot reach IRIS" ;;
    esac
fi
apps=$(os "$CONTAINER" <<'OBJECTSCRIPT'
zn "%SYS" write "webapp-phonebook=",##class(Security.Applications).Exists("/csp/phonebook"),!
zn "%SYS" write "webapp-company=",##class(Security.Applications).Exists("/csp/company"),!
halt
OBJECTSCRIPT
)
for line in $(echo "$apps" | grep -E '^webapp-'); do
    case "$line" in *=1) ok "$line" ;; *) bad "$line (Phonebook not installed?)" ;; esac
done

echo "== 6. Mail server =="
# Optional: it is behind the "mail" profile, and only four exercises need it.
if [ "$(docker inspect -f '{{.State.Running}}' "${MAIL_CONTAINER:-course-mail}" 2>/dev/null)" != "true" ]; then
    warn "the mail server is not running - the mail-notification exercises need it"
    note "Start it with: docker compose -f docker-compose.yml -f course-overlay.yml \\"
    note "                     --profile mail up -d"
elif docker exec "$CONTAINER" bash -c 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/mail/1025"' 2>/dev/null; then
    ok "IRIS can reach the mail server at mail:1025"
    note "Configure ^MONMGR and Task Manager with SMTP server 'mail', port 1025."
    note "Inbox: http://localhost:${MAIL_UI_PORT}"
else
    bad "the mail server is running but mail:1025 is not reachable from $CONTAINER"
fi

echo "== 7. OS accounts for the Authentication module =="
missing=$(docker exec "$CONTAINER" bash -c 'for u in sumi chris olaf anita bo vic robin fred; do id -u "$u" >/dev/null 2>&1 || echo -n "$u "; done')
if [ -z "$missing" ]; then
    ok "all eight OS accounts exist"
else
    bad "missing OS accounts: $missing"
    note "The image was probably built before these were added: docker compose build"
fi

echo "== 8. ISCAgent (Mirroring module) =="
if docker exec "$CONTAINER" bash -c 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/localhost/2188"' 2>/dev/null; then
    ok "ISCAgent listening on 2188"
else
    bad "ISCAgent is not listening on 2188"
fi

if [ "$DO_RESTART" -eq 1 ]; then
    echo "== 9. Instance stop/start and emergency access mode =="
    # This is the one part that changes the instance's state. It matters because
    # ~15 exercises say "Restart your instance" and two need emergency access mode,
    # and in a container IRIS is started by the entrypoint - so it has to be proven
    # that stopping IRIS does not take the container with it.
    EMERGENCY_ID=${EMERGENCY_ID:-emgcy}
    EMERGENCY_PW=${EMERGENCY_PW:-emgcy}

    docker exec "$CONTAINER" iris stop IRIS quietly >/dev/null 2>&1
    sleep 3
    if [ "$(docker inspect -f '{{.State.Status}}' "$CONTAINER")" = "running" ]; then
        ok "'iris stop IRIS' left the container running"
    else
        bad "the container died with IRIS - restart exercises will not work"
    fi

    # Counted, not matched: the log line stays in messages.log for good, so on a
    # second run a plain grep would pass without emergency mode having started.
    # "; true" inside the container, not "|| echo 0" outside: grep -c prints 0 and
    # *exits 1* when there is no match, so the fallback would append a second 0 and
    # the comparison below would die on "0\n0" - which is exactly what a first run
    # on a fresh instance produces.
    count_emergency_starts() {
        docker exec "$CONTAINER" bash -c \
            'grep -c "started with EmergencyId option" /usr/irissys/mgr/messages.log 2>/dev/null; true' \
            2>/dev/null | head -1
    }
    emg_before=$(count_emergency_starts); emg_before=${emg_before:-0}
    docker exec "$CONTAINER" iris start IRIS "EmergencyId=$EMERGENCY_ID,$EMERGENCY_PW" >/dev/null 2>&1
    sleep 5
    emg_after=$(count_emergency_starts); emg_after=${emg_after:-0}
    if [ "$emg_after" -gt "$emg_before" ]; then
        ok "emergency access mode starts (EmergencyId=$EMERGENCY_ID,...)"
    else
        bad "emergency access mode did not start"
    fi

    # Leaving emergency mode needs the emergency credentials on stdin: in emergency
    # mode "iris stop" itself prompts, and unauthenticated it aborts with "local
    # authentication failure" - leaving the instance up but rejecting every login,
    # including SuperUser. Feed them, or the environment is left unusable.
    printf '%s\n%s\n' "$EMERGENCY_ID" "$EMERGENCY_PW" |
        docker exec -i "$CONTAINER" iris stop IRIS quietly >/dev/null 2>&1
    sleep 3
    docker exec "$CONTAINER" iris start IRIS quietly >/dev/null 2>&1
    sleep 5
    # "iris list" says "running" for an emergency-mode instance too, so status is not
    # proof. A plain unauthenticated session is: only normal mode allows one.
    if echo "$(printf 'write "back=1",!\nhalt\n' | docker exec -i "$CONTAINER" iris session IRIS -U %SYS 2>&1)" |
        grep -q '^back=1'; then
        ok "instance came back in normal mode, ordinary logins work again"
    else
        bad "the instance is not usable again - it may still be in emergency mode"
        note "Recover with:"
        note "    printf '$EMERGENCY_ID\\n$EMERGENCY_PW\\n' | docker exec -i $CONTAINER iris stop IRIS quietly"
        note "    docker exec $CONTAINER iris start IRIS quietly"
    fi
else
    echo "== 9. Instance stop/start and emergency access mode =="
    note "skipped (--no-restart)"
fi

echo
if [ "$fails" -eq 0 ]; then
    if [ "$warns" -eq 0 ]; then
        echo "All checks passed - the course exercises can be carried out on this stack."
    else
        echo "No failures, $warns warning(s) - the exercises can be carried out; see above."
    fi
    echo "PREREQUISITES.md lists where the container differs from the printed notes."
else
    echo "$fails check(s) failed, $warns warning(s)." >&2
    exit 1
fi
