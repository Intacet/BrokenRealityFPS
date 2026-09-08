$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot
try {
    git -c "safe.directory=$projectRoot" status --short
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read Git status."
    }

    git -c "safe.directory=$projectRoot" diff --stat
    git -c "safe.directory=$projectRoot" diff --check
    if ($LASTEXITCODE -ne 0) {
        throw "The diff contains whitespace errors. Review them before committing."
    }

    Write-Host "Review the Source Control diff, then update AI_HANDOFF.md and CHANGELOG.md before committing."
} finally {
    Pop-Location
}
