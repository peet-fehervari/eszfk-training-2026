# Scripted equivalent of the course's "Applications" module: install the Phonebook
# application and the MIS.Simulation helper class. Windows counterpart of
# install-phonebook.sh.
#
# THIS SCRIPT DOES EXERCISE WORK, and it is the only one that does - which is why it is
# separate from prepare-instance.ps1 and optional. The %Installer it runs creates the
# databases, the PHONEBOOK namespace, the global mappings and the CSP applications that
# the "Configuration for the Application" and "Applications" modules have the participant
# create by hand. Skip it if those modules are to be done properly.
#
# Run it when they are not: to prepare a demo instance, or to get the later modules
# working without replaying the earlier ones - backup, journalling, ECP, mirroring and
# every authorization module operate on the databases this creates, so a participant who
# gets stuck in the earlier modules is stuck in all of them.
#
# Nothing is hard-coded: every path is a parameter with the course's own default.
#   -StudentDir  where the student files are inside the container
#   -DbDir       parent directory for the application databases
#   -BackupDir   where MIS.Simulation.Backup() writes; stored in a global, so a
#                non-default value here survives for the exercises too
#
# Works on any instance in any stack; run prepare-instance.ps1 on it first.
#
# Usage:  .\install-phonebook.ps1 <container>
param(
    [string]$Container = $env:COURSE_CONTAINER,
    [string]$StudentDir = $(if ($env:STUDENT_DIR) { $env:STUDENT_DIR } else { '/Management/' }),
    [string]$DbDir = $(if ($env:DB_DIR) { $env:DB_DIR } else { '/databases/' }),
    [string]$BackupDir = $(if ($env:BACKUP_DIR) { $env:BACKUP_DIR } else { '/backups' })
)

. "$PSScriptRoot\..\setup-lib.ps1"

if (-not $Container) {
    Write-Host "Usage: .\install-phonebook.ps1 <container>    e.g. .\install-phonebook.ps1 training-health"
    exit 2
}

Assert-ContainerRunning $Container

Write-Host "Installing the Phonebook application on $Container"
Write-Host "  student files: $StudentDir"
Write-Host "  databases:     $DbDir"

# The installer creates CUSTOMER, PERSONAL, PBCODE and COMPANY, three namespaces,
# two global mappings and four CSP applications, then populates 5 rows per table.
# It is not idempotent in the interesting sense: PHONEBOOK is Create="overwrite",
# so re-running it resets the namespace but leaves existing data in the databases.
#
# Every marker is written with a leading "!" on purpose. The installer logs its own
# progress and leaves the cursor mid-line, so a marker written without it lands at the
# end of that line - where Test-Steps' anchored pattern cannot see it, and a failed
# install is reported as a success.
$output = Invoke-Iris -Container $Container -Lines @(
    ('set sc=$system.OBJ.Load("{0}PhonebookInstaller.xml","ck") write !,"load-installer=",$system.Status.IsOK(sc),!' -f $StudentDir)
    'write:''$system.Status.IsOK(sc) "  ",$system.Status.GetErrorText(sc),!'
    ('set sc=##class(Phonebook.Installer).RunInstall("{0}","{1}",1) write !,"run-install=",$system.Status.IsOK(sc),!' -f $StudentDir, $DbDir)
    'write:''$system.Status.IsOK(sc) "  ",$system.Status.GetErrorText(sc),!'
    'halt'
)

Select-Lines -Output $output -Pattern '^(load-installer|run-install|  )'
if (-not (Test-Steps -Output $output)) {
    Write-Host "Phonebook installation incomplete."
    # By far the most common cause: the databases were installed once already. The
    # installer will not create a database over an existing IRIS.DAT ("ERROR #20: the
    # file already exists"), and after a container recreate the files outlive the
    # instance configuration that referenced them.
    Write-Host "If the error mentions a file that already exists, the databases are left over"
    Write-Host "from an earlier install. Start from a clean stack (docker compose down -v),"
    Write-Host "or empty $DbDir in the container first."
    exit 1
}

# MIS.Simulation goes into PHONEBOOK, which only exists after the step above.
Write-Host "Importing MIS.Simulation into PHONEBOOK"
$output = Invoke-Iris -Container $Container -Lines @(
    ('zn "PHONEBOOK" set sc=$system.OBJ.Load("{0}MIS.Simulation.xml","ck") write !,"load-simulation=",$system.Status.IsOK(sc),!' -f $StudentDir)
    'write:''$system.Status.IsOK(sc) "  ",$system.Status.GetErrorText(sc),!'
    ('zn "PHONEBOOK" set:"{0}"''="/backups" ^MIS.Simulation("Backup","backupdir")="{0}"' -f $BackupDir)
    'halt'
)

Select-Lines -Output $output -Pattern '^(load-simulation|  )'
if (-not (Test-Steps -Output $output)) {
    Write-Host "MIS.Simulation import failed."
    exit 1
}

if ($BackupDir -ne '/backups') {
    Write-Host "  MIS.Simulation backup directory set to $BackupDir"
}

Write-Host ""
Write-Host "Done. This instance now has the PHONEBOOK namespace, the COMPANY, CUSTOMER,"
Write-Host "PERSONAL and PBCODE databases, and the /csp/phonebook and /csp/company"
Write-Host "applications - so the exercises can be started at the Applications module."
