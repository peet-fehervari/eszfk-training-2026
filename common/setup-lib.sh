# Helpers for the stacks' setup and verify scripts.
#
# These run on the HOST and reach into containers with docker exec. They are not
# executed inside a container - common/ is also bind-mounted into the instances,
# but this file is unused there.
#
# Sourced, not executed:  . ../../common/setup-lib.sh

# Run ObjectScript in an instance, one complete command per line on stdin.
#
# Piped input is read by `iris session` as if typed at the %SYS> prompt, so every
# line must be a complete command. Multi-line constructs - FOR blocks, IF blocks,
# $$$ macros - fail with <SYNTAX>. Keep each step on one line and end with `halt`.
os() {
    local container=$1
    docker exec -i "$container" iris session IRIS -U %SYS 2>&1
}

# Fail unless the container exists and is running.
need_running() {
    local container=$1
    if [ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" != "true" ]; then
        echo "ERROR: container '$container' is not running." >&2
        echo "       Start the stack first: docker compose up -d" >&2
        exit 1
    fi
}

# Steps report their outcome as "<label>=1" or "<label>=0"; treat any 0 as fatal so
# a half-configured stack is not reported as success. IRIS itself exits 0 even when
# a method returns an error status, so the exit code cannot be relied on.
check_steps() {
    local output=$1
    if echo "$output" | grep -q '=0$'; then
        echo "$output" | grep '=0$' | sed 's/^/  FAILED: /' >&2
        return 1
    fi
    return 0
}
