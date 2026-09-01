# Helpers for the host scripts in common/course/, PowerShell edition.
#
# This is the Windows counterpart of setup-lib.sh next to it. Same function, same
# output, same step-marker contract - so a participant on Windows runs the .ps1 and a
# participant on WSL or Linux runs the .sh, and both see the same lines.
#
# Dot-sourced, not executed:  . "$PSScriptRoot\..\setup-lib.ps1"
#
# Works in Windows PowerShell 5.1 (the one in every Windows install) as well as
# PowerShell 7, so nothing newer than 5.1 syntax is used here.

# Do not send a UTF-8 byte-order mark down the pipe to `iris session`: it would arrive
# as the first characters of the first command and fail with <SYNTAX>.
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

# Fail unless the container exists and is running.
function Assert-ContainerRunning {
    param([Parameter(Mandatory = $true)][string]$Container)

    $running = docker inspect -f '{{.State.Running}}' $Container 2>$null
    if ("$running".Trim() -ne 'true') {
        Write-Host "ERROR: container '$Container' is not running."
        Write-Host "       Start the stack first: docker compose up -d"
        exit 1
    }
}

# Run ObjectScript in an instance. Takes the commands as an array, one complete
# command per element.
#
# Piped input is read by `iris session` as if typed at the %SYS> prompt, so every line
# must be a complete command: multi-line constructs - FOR blocks, IF blocks, $$$
# macros - fail with <SYNTAX>. End with 'halt'.
#
# The lines are joined with a bare LF on purpose. This file is checked out with CRLF on
# Windows, and a CR travelling into the session becomes part of the command and breaks
# it - the single most likely thing to go wrong in the Windows version of a script.
function Invoke-Iris {
    param(
        [Parameter(Mandatory = $true)][string]$Container,
        [Parameter(Mandatory = $true)][string[]]$Lines
    )

    $stdin = ($Lines -join "`n") + "`n"
    $stdin | docker exec -i $Container iris session IRIS -U %SYS 2>&1
}

# Steps report their outcome as "<label>=1" or "<label>=0"; treat any 0 as fatal so a
# half-configured stack is not reported as success. IRIS itself exits 0 even when a
# method returns an error status, so the exit code cannot be relied on.
#
# A step marker is a whole line and nothing else: label, "=", one digit. Anchoring both
# ends matters - %Installer's own progress log ends lines with text like
# "(isdir=0) into PHONEBOOK, recurse=0", which a loose match reads as a failed step and
# turns a successful install into a reported failure.
#
# Each line is trimmed before matching: docker hands back lines that still carry a CR,
# and "=0`r" does not match a pattern anchored with $.
#
# The three functions below all take the captured output as -Output, and all three need
# [AllowEmptyString()]: a Mandatory parameter rejects an empty string even when it is one
# element inside an array, and an `iris session` transcript is full of blank lines. Without
# it every call fails with "Cannot bind argument to parameter 'Output'".
$StepMarker = '^[A-Za-z][A-Za-z0-9_.-]*=[0-9]$'

function Test-Steps {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Output)

    $failed = @()
    foreach ($line in $Output) {
        $trimmed = "$line".Trim()
        if ($trimmed -match $StepMarker -and $trimmed -match '=0$') { $failed += $trimmed }
    }
    if ($failed.Count -gt 0) {
        foreach ($f in $failed) { Write-Host "  FAILED: $f" }
        return $false
    }
    return $true
}

# Print the lines a script wants to show, the way `grep -E` does in the .sh version.
function Select-Lines {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Output,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    foreach ($line in $Output) {
        $trimmed = "$line".TrimEnd()
        if ($trimmed -match $Pattern) { $trimmed }
    }
}

# Value of a single "label=value" line, or an empty string.
function Get-StepValue {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Output,
        [Parameter(Mandatory = $true)][string]$Label
    )

    foreach ($line in $Output) {
        $trimmed = "$line".Trim()
        if ($trimmed -like "$Label=*") { return $trimmed.Substring($Label.Length + 1) }
    }
    return ''
}
