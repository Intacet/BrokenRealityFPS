$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot
try {
    $pending = @(git -c "safe.directory=$projectRoot" status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read Git status."
    }
    if ($pending.Count -gt 0) {
        Write-Host "Local changes are present. Review or checkpoint them before pulling."
        git -c "safe.directory=$projectRoot" status --short
        exit 1
    }

    git -c "safe.directory=$projectRoot" pull --ff-only origin main
    if ($LASTEXITCODE -ne 0) {
        throw "Git could not fast-forward main. Review the branch before continuing."
    }

    Write-Host "Broken Reality is ready on main. Read docs/AI_HANDOFF.md before editing."
} finally {
    Pop-Location
}
