# Adds the "Managing InterSystems Servers" course prerequisites to an IRIS instance
# that is already running - any instance, in any of the stacks in this repository.
# Windows counterpart of prepare-instance.sh: same steps, same output.
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
# "Applications" module - see install-phonebook.ps1 next to this script.
#
# Persistence. The course directories are named volumes in every stack's compose file, so
# what is in them survives a recreate. Docker creates the mount point for a path that does
# not exist in the image root-owned, though, so the volumes alone are not usable - fixing
# their ownership is what this script is for. The OS accounts are different: they live in
# the container's writable layer and any recreate loses them, so re-run this script after
# one. It is idempotent and leaves a populated /Management alone.
#
# Usage:  .\prepare-instance.ps1 <container> [container ...]
#         .\prepare-instance.ps1 training-ecp-code training-ecp-data
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Containers
)

. "$PSScriptRoot\..\setup-lib.ps1"

$MaterialDir   = if ($env:COURSE_MATERIAL_DIR) { $env:COURSE_MATERIAL_DIR } else { Join-Path $PSScriptRoot 'material' }
$ManagementDir = if ($env:MANAGEMENT_DIR) { $env:MANAGEMENT_DIR } else { '/Management' }
$IrisUid       = if ($env:IRIS_UID) { $env:IRIS_UID } else { '51773' }

# Every path the exercise text types. Overridable, but then the notes cannot be followed
# literally, which is the whole point of using these.
$CourseDirs = if ($env:COURSE_DIRS) { $env:COURSE_DIRS } else {
    "$ManagementDir /databases /backups /journals/jrn /journals/altjrn /InterSystems/training/encryptionkey"
}

# The accounts the delegated-authentication and OS-authentication exercises use.
$CourseOsUsers = if ($env:COURSE_OS_USERS) { $env:COURSE_OS_USERS } else {
    'sumi:sumi chris:chris olaf:olaf anita:anita bo:bobo vic:vic robin:robin fred:fred'
}

if (-not $Containers -or $Containers.Count -eq 0) {
    Write-Host "Usage: .\prepare-instance.ps1 <container> [container ...]"
    Write-Host "       e.g. .\prepare-instance.ps1 training-health"
    exit 2
}

$script:fails = 0
function ok   { param([string]$Message) Write-Host "  OK      $Message" }
function bad  { param([string]$Message) Write-Host "  FAILED  $Message"; $script:fails++ }
function note { param([string]$Message) Write-Host "          $Message" }

foreach ($container in $Containers) {
    Write-Host "== $container =="
    Assert-ContainerRunning $container

    # 1. Directories. A named volume mounted over a path that does not exist in the image
    # arrives root-owned and IRIS cannot write it, so the chown is the point of this step,
    # not the mkdir. Doing it as root is why no image build is needed.
    docker exec -u root $container bash -c "mkdir -p $CourseDirs && chown -R ${IrisUid}:${IrisUid} $CourseDirs" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        ok "course directories created and owned by uid $IrisUid"
        note $CourseDirs
    }
    else {
        bad "could not create the course directories"
    }

    # 2. OS accounts. Skipped individually if already present, so this survives re-runs
    # and instances that were built from the course image.
    $created = ''
    $existing = ''
    foreach ($entry in ($CourseOsUsers -split '\s+')) {
        if (-not $entry) { continue }
        $user, $pass = $entry -split ':', 2
        docker exec -u root $container id -u $user 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $existing += "$user "
            continue
        }
        docker exec -u root $container bash -c "useradd --create-home --shell /bin/bash '$user' && echo '${user}:${pass}' | chpasswd" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $created += "$user " } else { bad "could not create OS account $user" }
    }
    if ($created)  { ok "OS accounts created: $created" }
    if ($existing) { ok "OS accounts already present: $existing" }

    # 3. Student files. Copied rather than mounted, because the exercises write into
    # /Management (^%GO exports, the %ZSTOP ss.txt) and a read-only mount cannot take
    # that. A README.md on either side is skipped: it is never course material, and
    # counting one would make an otherwise empty directory look populated.
    $material = @()
    if (Test-Path $MaterialDir) {
        $material = @(Get-ChildItem -LiteralPath $MaterialDir -Force | Where-Object { $_.Name -ne 'README.md' })
    }
    $inContainer = docker exec $container bash -c "find $ManagementDir -mindepth 1 -not -name README.md -print -quit 2>/dev/null"

    if ($material.Count -eq 0) {
        bad "no student files in $MaterialDir"
        note "They are licensed material and are handed out separately."
        note "Placement instructions: README.md next to this script."
    }
    elseif ("$inContainer".Trim()) {
        ok "$ManagementDir already populated, left alone"
        note "Anything done during the exercises is preserved. To reseed, empty it first."
    }
    else {
        $copied = 0
        foreach ($entry in $material) {
            docker cp $entry.FullName "${container}:$ManagementDir/" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $copied++ }
        }
        # docker cp writes as root, so the ownership has to be fixed afterwards.
        docker exec -u root $container chown -R "${IrisUid}:${IrisUid}" $ManagementDir 2>$null | Out-Null
        if ($copied -gt 0) {
            ok "$copied item(s) copied into $ManagementDir, owned by uid $IrisUid"
        }
        else {
            bad "nothing could be copied into $ManagementDir"
        }
    }
    Write-Host ""
}

if ($script:fails -eq 0) {
    Write-Host "Prerequisites in place. The exercises can be started."
    Write-Host "Re-run this script at any time to check or repair the same things."
    Write-Host ""
    Write-Host "Optional: .\install-phonebook.ps1 <container> installs the Phonebook application"
    Write-Host "instead of the participant. Skip it if the ""Configuration for the Application"""
    Write-Host "and ""Applications"" modules are to be done by hand."
}
else {
    Write-Host "$($script:fails) step(s) failed."
    exit 1
}
