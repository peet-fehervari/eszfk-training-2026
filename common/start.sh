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
set -u

KEY_ROOT=${IRIS_KEY_ROOT:-/irisdev/keys}

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
