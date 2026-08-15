[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$GitArgs)

    $output = & git @GitArgs 2>$null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Git operation failed with exit code $exitCode."
    }
    return $output
}

$insideWorkTree = (Invoke-Git -GitArgs @("rev-parse", "--is-inside-work-tree") | Select-Object -First 1).Trim()
if ($insideWorkTree -ne "true") {
    throw "Run sot-publish.ps1 from a Git working tree."
}

$scriptRepository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$currentRepositoryText = (Invoke-Git -GitArgs @("rev-parse", "--show-toplevel") | Select-Object -First 1).Trim()
$currentRepository = (Resolve-Path -LiteralPath $currentRepositoryText).Path
$pathComparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
} else {
    [System.StringComparison]::Ordinal
}
if (-not $scriptRepository.Equals($currentRepository, $pathComparison)) {
    throw "Run this controlled entrypoint from its Ship_of_Theseus worktree."
}

$branch = (Invoke-Git -GitArgs @("symbolic-ref", "--quiet", "--short", "HEAD") | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw "Detached HEAD cannot be published. Check out the assigned task branch."
}

$protectedBranches = @("develop", "main", "master")
if ($protectedBranches -contains $branch.ToLowerInvariant()) {
    throw "Branch '$branch' is protected and cannot be published directly."
}

$null = Invoke-Git -GitArgs @("check-ref-format", "--branch", $branch)
$null = Invoke-Git -GitArgs @("remote", "get-url", "origin")
$status = @(Invoke-Git -GitArgs @("status", "--porcelain"))
if ($status.Count -ne 0) {
    throw "Working tree is not clean. Commit changes before publishing."
}

if ($DryRun) {
    Write-Output "Dry-run: current task branch '$branch' would be published to origin with the same name."
    exit 0
}

$refspec = "HEAD:refs/heads/$branch"
$null = Invoke-Git -GitArgs @("push", "--porcelain", "origin", $refspec)
Write-Output "Published current task branch '$branch' to origin with the same name."
