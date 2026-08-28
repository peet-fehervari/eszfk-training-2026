#!/bin/bash
# Step 1 of the ECP exercise, scripted: prepare the DATA instance to serve its
# database to other instances.
#
# Portal equivalent:
#   System Administration > Security > Services > %Service_ECP > Service Enabled
#
# Run this only to reset the environment or to demonstrate the finished state -
# doing it by hand is the exercise. See ../EXERCISE.md.
set -euo pipefail

cd "$(dirname "$0")"
. ../../common/setup-lib.sh

DATA_CONTAINER=${DATA_CONTAINER:-training-ecp-data}

need_running "$DATA_CONTAINER"

echo "Enabling %Service_ECP on $DATA_CONTAINER ..."

# ECP is disabled by default on 2026.1. Without it the code instance cannot mount
# this instance's database and fails with a connection error.
output=$(os "$DATA_CONTAINER" <<'OBJECTSCRIPT'
set p("Enabled")=1 set sc=##class(Security.Services).Modify("%Service_ECP",.p)
write:'$system.Status.IsOK(sc) "  error: ",$system.Status.GetErrorText(sc),!
write "enable-ecp-service=",$system.Status.IsOK(sc),!
set sc=##class(Security.Services).Get("%Service_ECP",.q)
write "ecp-service-now-enabled=",+$get(q("Enabled")),!
halt
OBJECTSCRIPT
)

echo "$output" | grep -E '^(enable-ecp-service|ecp-service-now-enabled|  error)' || true
check_steps "$output"

echo "Done. The data instance now accepts ECP connections."
echo "Next: ./02-code-server.sh"
