#!/usr/bin/env bash
# Scripted equivalent of the course's "Applications" module: install the Phonebook
# application and the MIS.Simulation helper class.
#
# The course has the participant do this by hand (import the %Installer class in
# the portal, then call RunInstall from Terminal). Run this to prepare a demo
# instance, to reset one, or to get the later modules working without replaying
# the earlier ones - backup, journalling, ECP, mirroring and every authorization
# module operate on the databases this creates.
#
# Nothing is hard-coded: every path is a variable with the course's own default.
#   STUDENT_DIR  where the student files are inside the container
#   DB_DIR       parent directory for the application databases
#   BACKUP_DIR   where MIS.Simulation.Backup() writes; stored in a global, so a
#                non-default value here survives for the exercises too
#
# Works on any instance in any stack; run prepare-instance.sh on it first.
#
# Usage:  ./install-phonebook.sh <container>
set -euo pipefail
cd "$(dirname "$0")"
. ../setup-lib.sh

CONTAINER=${1:-${COURSE_CONTAINER:-}}
if [ -z "$CONTAINER" ]; then
    echo "Usage: $0 <container>    e.g. $0 training-health" >&2
    exit 2
fi
STUDENT_DIR=${STUDENT_DIR:-/Management/}
DB_DIR=${DB_DIR:-/databases/}
BACKUP_DIR=${BACKUP_DIR:-/backups}

need_running "$CONTAINER"

echo "Installing the Phonebook application on $CONTAINER"
echo "  student files: $STUDENT_DIR"
echo "  databases:     $DB_DIR"

# The installer creates CUSTOMER, PERSONAL, PBCODE and COMPANY, three namespaces,
# two global mappings and four CSP applications, then populates 5 rows per table.
# It is not idempotent in the interesting sense: PHONEBOOK is Create="overwrite",
# so re-running it resets the namespace but leaves existing data in the databases.
#
# Every marker is written with a leading "!" on purpose. The installer logs its own
# progress and leaves the cursor mid-line, so a marker written without it lands at the
# end of that line - where check_steps' anchored pattern cannot see it, and a failed
# install is reported as a success.
output=$(os "$CONTAINER" <<OBJECTSCRIPT
set sc=\$system.OBJ.Load("${STUDENT_DIR}PhonebookInstaller.xml","ck") write !,"load-installer=",\$system.Status.IsOK(sc),!
write:'\$system.Status.IsOK(sc) "  ",\$system.Status.GetErrorText(sc),!
set sc=##class(Phonebook.Installer).RunInstall("$STUDENT_DIR","$DB_DIR",1) write !,"run-install=",\$system.Status.IsOK(sc),!
write:'\$system.Status.IsOK(sc) "  ",\$system.Status.GetErrorText(sc),!
halt
OBJECTSCRIPT
)

echo "$output" | grep -E '^(load-installer|run-install|  )' || true
if ! check_steps "$output"; then
    echo "Phonebook installation incomplete." >&2
    # By far the most common cause: the databases were installed once already. The
    # installer will not create a database over an existing IRIS.DAT ("ERROR #20: the
    # file already exists"), and after a container recreate the files outlive the
    # instance configuration that referenced them.
    echo "If the error mentions a file that already exists, the databases are left over" >&2
    echo "from an earlier install. Start from a clean stack (docker compose down -v)," >&2
    echo "or empty $DB_DIR in the container first." >&2
    exit 1
fi

# MIS.Simulation goes into PHONEBOOK, which only exists after the step above.
echo "Importing MIS.Simulation into PHONEBOOK"
output=$(os "$CONTAINER" <<OBJECTSCRIPT
zn "PHONEBOOK" set sc=\$system.OBJ.Load("${STUDENT_DIR}MIS.Simulation.xml","ck") write !,"load-simulation=",\$system.Status.IsOK(sc),!
write:'\$system.Status.IsOK(sc) "  ",\$system.Status.GetErrorText(sc),!
zn "PHONEBOOK" set:"$BACKUP_DIR"'="/backups" ^MIS.Simulation("Backup","backupdir")="$BACKUP_DIR"
halt
OBJECTSCRIPT
)

echo "$output" | grep -E '^(load-simulation|  )' || true
check_steps "$output" || { echo "MIS.Simulation import failed." >&2; exit 1; }

if [ "$BACKUP_DIR" != "/backups" ]; then
    echo "  MIS.Simulation backup directory set to $BACKUP_DIR"
fi

echo
echo "Done. Verify with ./verify.sh"
