#!/usr/bin/env bash
# Adds the "Managing InterSystems Servers" course prerequisites to an IRIS instance
# that is already running - any instance, in any of the stacks in this repository.
#
# Runs on the HOST and reaches into the container. Nothing here needs an image build:
# the directories and the OS accounts are created at runtime with `docker exec -u root`,
# which is why the course does not need a stack of its own.
#
# What it does, all idempotent, so re-running it is harmless:
#   1. creates the six directories the exercise text names, owned by the IRIS user
#   2. creates the eight OS accounts the authentication module logs in as
#   3. copies the student files into /Management, which is writable, so the exercises
#      that export there work too
#
# What it deliberately does NOT do: install the Phonebook application. That is the
# "Applications" module - see install-phonebook.sh next to this script.
#
# Persistence. The course directories are named volumes in every stack's compose file, so
# what is in them survives a recreate. Docker creates the mount point for a path that does
# not exist in the image root-owned, though, so the volumes alone are not usable - fixing
# their ownership is what this script is for. The OS accounts are different: they live in
# the container's writable layer and any recreate loses them, so re-run this script after
# one. It is idempotent and leaves a populated /Management alone.
#
# Usage:  ./prepare-instance.sh <container> [container ...]
#         ./prepare-instance.sh training-ecp-code training-ecp-data
set -euo pipefail
cd "$(dirname "$0")"
. ../setup-lib.sh

MATERIAL_DIR=${COURSE_MATERIAL_DIR:-./material}
MANAGEMENT_DIR=${MANAGEMENT_DIR:-/Management}
IRIS_UID=${IRIS_UID:-51773}

# Every path the exercise text types. Overridable, but then the notes cannot be followed
# literally, which is the whole point of using these.
COURSE_DIRS=${COURSE_DIRS:-"$MANAGEMENT_DIR /databases /backups /journals/jrn /journals/altjrn /InterSystems/training/encryptionkey"}

# The accounts the delegated-authentication and OS-authentication exercises use.
COURSE_OS_USERS=${COURSE_OS_USERS:-"sumi:sumi chris:chris olaf:olaf anita:anita bo:bobo vic:vic robin:robin fred:fred"}

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <container> [container ...]" >&2
    echo "       e.g. $0 training-health" >&2
    exit 2
fi

fails=0
ok()   { echo "  OK      $*"; }
bad()  { echo "  FAILED  $*"; fails=$((fails+1)); }
note() { echo "          $*"; }

for container in "$@"; do
    echo "== $container =="
    need_running "$container"

    # 1. Directories. A named volume mounted over a path that does not exist in the image
    # arrives root-owned and IRIS cannot write it, so the chown is the point of this step,
    # not the mkdir. Doing it as root is why no image build is needed.
    if docker exec -u root "$container" bash -c \
        "mkdir -p $COURSE_DIRS && chown -R $IRIS_UID:$IRIS_UID $COURSE_DIRS" 2>/dev/null; then
        ok "course directories created and owned by uid $IRIS_UID"
        note "$COURSE_DIRS"
    else
        bad "could not create the course directories"
    fi

    # 2. OS accounts. Skipped individually if already present, so this survives re-runs
    # and instances that were built from the course image.
    created=""
    existing=""
    for entry in $COURSE_OS_USERS; do
        user="${entry%%:*}"
        pass="${entry#*:}"
        if docker exec -u root "$container" id -u "$user" >/dev/null 2>&1; then
            existing="$existing$user "
        elif docker exec -u root "$container" bash -c \
            "useradd --create-home --shell /bin/bash '$user' && echo '$user:$pass' | chpasswd" \
            >/dev/null 2>&1; then
            created="$created$user "
        else
            bad "could not create OS account $user"
        fi
    done
    [ -n "$created" ] && ok "OS accounts created: $created"
    [ -n "$existing" ] && ok "OS accounts already present: $existing"

    # 3. Student files. Copied rather than mounted, because the exercises write into
    # /Management (^%GO exports, the %ZSTOP ss.txt) and a read-only mount cannot take
    # that. A README.md on either side is skipped: it is never course material, and
    # counting one would make an otherwise empty directory look populated.
    if [ ! -d "$MATERIAL_DIR" ] ||
       [ -z "$(find "$MATERIAL_DIR" -mindepth 1 -not -name README.md -print -quit)" ]; then
        bad "no student files in $MATERIAL_DIR"
        note "They are licensed material and are handed out separately."
        note "Placement instructions: README.md next to this script."
    elif [ -n "$(docker exec "$container" bash -c \
            "find $MANAGEMENT_DIR -mindepth 1 -not -name README.md -print -quit 2>/dev/null")" ]; then
        ok "$MANAGEMENT_DIR already populated, left alone"
        note "Anything done during the exercises is preserved. To reseed, empty it first."
    else
        copied=0
        while IFS= read -r entry; do
            docker cp "$entry" "$container:$MANAGEMENT_DIR/" >/dev/null 2>&1 && copied=$((copied+1))
        done < <(find "$MATERIAL_DIR" -mindepth 1 -maxdepth 1 -not -name README.md)
        # docker cp writes as root, so the ownership has to be fixed afterwards.
        docker exec -u root "$container" chown -R "$IRIS_UID:$IRIS_UID" "$MANAGEMENT_DIR" 2>/dev/null || true
        if [ "$copied" -gt 0 ]; then
            ok "$copied item(s) copied into $MANAGEMENT_DIR, owned by uid $IRIS_UID"
        else
            bad "nothing could be copied into $MANAGEMENT_DIR"
        fi
    fi
    echo
done

if [ "$fails" -eq 0 ]; then
    echo "Prerequisites in place. The exercises can be started."
    echo "Re-run this script at any time to check or repair the same things."
    echo
    echo "Optional: ./install-phonebook.sh <container> installs the Phonebook application"
    echo "instead of the participant. Skip it if the \"Configuration for the Application\""
    echo "and \"Applications\" modules are to be done by hand."
else
    echo "$fails step(s) failed." >&2
    exit 1
fi
