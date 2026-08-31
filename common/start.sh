#!/bin/bash
# Shared IRIS container entrypoint for all training stacks.
#
# Its only job is to find the licence key and hand it to iris-main. Everything
# stack-specific belongs in the stack directory, not here.
#
# The key is never baked into an image and never committed. It lives in a key
# store mounted read-only, organised one sub-directory per licence year:
#     <key store>/2026/iris.key
# The newest year directory wins, so next year's key is picked up by dropping it
# in without touching any file here.
#
# Started as: /tini -- common/start.sh
# tini must stay the parent so signals reach IRIS and it shuts down cleanly,
# which is why this script ends in `exec`.
#
# Deliberately NOT passed to iris-main:
#   --check-caps   On 2026.1 iris-main documents this as "Does nothing; retained
#                  for backwards compatibility". Older projects still pass it.
#   -a <command>   The post-start hook. These stacks are configured by hand as
#                  part of the training exercise, so nothing runs automatically.
#                  See the stack EXERCISE.md files.
#
# One optional extra job, used only by the sysadmin-course stack: seed a writable
# working directory from a read-only mount. Both paths come from the environment
# and nothing happens unless COURSE_MATERIAL_SRC is set, so the other stacks are
# unaffected.
set -u

KEY_ROOT=${IRIS_KEY_ROOT:-/irisdev/keys}

MATERIAL_SRC=${COURSE_MATERIAL_SRC:-}
MATERIAL_DEST=${COURSE_MATERIAL_DEST:-}
if [ -n "$MATERIAL_SRC" ] && [ -n "$MATERIAL_DEST" ] && [ -d "$MATERIAL_SRC" ]; then
    # README.md is the placement instructions committed to the source directory, not
    # material. Ignoring it on both sides matters: an instance started before the
    # material was dropped in must still seed itself on the next restart, and it
    # would not if a lone copied README counted as "already populated".
    src_files=$(find "$MATERIAL_SRC" -mindepth 1 -not -name README.md -print -quit 2>/dev/null)
    dest_files=$(find "$MATERIAL_DEST" -mindepth 1 -not -name README.md -print -quit 2>/dev/null)
    if [ -z "$src_files" ]; then
        echo "iris-init: WARNING - $MATERIAL_SRC is empty, nothing to seed"
        echo "iris-init: the course exercises need the student files there first."
        echo "iris-init: See the instructions in that directory's README.md."
    elif [ -n "$dest_files" ]; then
        echo "iris-init: $MATERIAL_DEST already populated, left alone"
    else
        # The exercises write into the destination (^%GO exports, %ZSTOP's ss.txt),
        # so a restart must not overwrite the participant's own work.
        echo "iris-init: seeding $MATERIAL_DEST from $MATERIAL_SRC"
        find "$MATERIAL_SRC" -mindepth 1 -maxdepth 1 -not -name README.md \
            -exec cp -r {} "$MATERIAL_DEST"/ \; 2>&1 ||
            echo "iris-init: WARNING - seeding failed"
    fi
fi

ARGS=()

key=""
for year_dir in $(ls -1d "$KEY_ROOT"/[0-9][0-9][0-9][0-9] 2>/dev/null | sort -r); do
    key=$(ls -1 "$year_dir"/*.key 2>/dev/null | head -n 1)
    [ -n "$key" ] && break
done

if [ -n "$key" ]; then
    echo "iris-init: licence key $key"
    ARGS+=(--key "$key")
else
    echo "iris-init: WARNING - no *.key found under $KEY_ROOT/<year>/"
    echo "iris-init: starting UNLICENSED. The community licence allows 5 concurrent"
    echo "iris-init: connections and permits neither ECP nor mirroring, so the"
    echo "iris-init: code/data and mirror stacks cannot be completed like this."
    echo "iris-init: Set IRIS_KEY_DIR to the key store - see the repository README."
fi

exec /iris-main "${ARGS[@]}"
