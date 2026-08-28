#!/bin/bash
# Step 2 of the ECP exercise, scripted: point the CODE instance at the data
# instance and move the TRAINING namespace's data - and only its data - there.
#
# After this, the TRAINING namespace on the code instance has:
#   Routines = TRAINCODE    local, holds the classes, routines and utilities
#   Globals  = REMOTEDATA   remote over ECP, physically on the data instance
#
# Portal equivalents:
#   System Administration > Configuration > Connectivity > ECP Settings
#     > "Data Servers" > Add Data Server
#   System Administration > Configuration > System Configuration > Local Databases
#     > Create New Database > "Remote Database"
#   System Administration > Configuration > System Configuration > Namespaces
#     > TRAINING > change the global database
#
# Run this only to reset the environment or to demonstrate the finished state.
set -euo pipefail

cd "$(dirname "$0")"
. ../../common/setup-lib.sh

CODE_CONTAINER=${CODE_CONTAINER:-training-ecp-code}
# Docker service name of the data instance on the stack network, and the native
# superserver port inside the container - not the published host port.
DATA_HOST=${DATA_HOST:-data}
DATA_PORT=${DATA_PORT:-1972}
# Path of the database as it exists ON the data instance.
REMOTE_DIR=${REMOTE_DIR:-/usr/irissys/mgr/traindata/}

need_running "$CODE_CONTAINER"

echo "Wiring $CODE_CONTAINER to $DATA_HOST:$DATA_PORT ..."

output=$(os "$CODE_CONTAINER" <<OBJECTSCRIPT
set e("Address")="$DATA_HOST",e("Port")=$DATA_PORT set sc=##class(Config.ECPServers).Create("DATA",.e)
write:'\$system.Status.IsOK(sc) "  error: ",\$system.Status.GetErrorText(sc),!
write "ecp-server-definition=",\$system.Status.IsOK(sc),!
set d("Directory")="$REMOTE_DIR",d("Server")="DATA" set sc=##class(Config.Databases).Create("REMOTEDATA",.d)
write:'\$system.Status.IsOK(sc) "  error: ",\$system.Status.GetErrorText(sc),!
write "remote-database=",\$system.Status.IsOK(sc),!
set n("Globals")="REMOTEDATA" set sc=##class(Config.Namespaces).Modify("TRAINING",.n)
write:'\$system.Status.IsOK(sc) "  error: ",\$system.Status.GetErrorText(sc),!
write "namespace-globals-remapped=",\$system.Status.IsOK(sc),!
write "globals-destination=",##class(%SYS.Namespace).GetGlobalDest("TRAINING"),!
halt
OBJECTSCRIPT
)

echo "$output" | grep -E '^(ecp-server-definition|remote-database|namespace-globals-remapped|globals-destination|  error)' || true
check_steps "$output"

echo "Done. Verify with ./verify.sh"
