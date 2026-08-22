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

function Get-RepositoryCommonDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string]$LogicalName
    )

    $inside = & git -C $RepositoryPath rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or ($inside | Select-Object -First 1).Trim() -ne "true") {
        throw "$LogicalName is not a valid Git working tree."
    }

    $commonDirectoryText = & git -C $RepositoryPath rev-parse --path-format=absolute --git-common-dir 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not identify the $LogicalName Git repository."
    }

    try {
        return (Resolve-Path -LiteralPath ($commonDirectoryText | Select-Object -First 1).Trim()).Path
    } catch {
        throw "Could not identify the $LogicalName Git repository."
    }
}

function Get-ConfiguredRepositoryRoots {
    param([Parameter(Mandatory = $true)][string]$ScriptRepository)

    $configuredRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($environmentName in @("SOT_DESIGNLIB_ROOT", "SOT_KB_ROOT")) {
        $value = [Environment]::GetEnvironmentVariable($environmentName)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $configuredRoots.Add($value)
        }
    }

    $localRootsPath = Join-Path $ScriptRepository ".codex/project/sot-roots.local.toml"
    if (Test-Path -LiteralPath $localRootsPath -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $localRootsPath) {
            if ($line -match "^\s*(?:designlib_root|kb_root)\s*=\s*'([^']*)'\s*(?:#.*)?$") {
                if (-not [string]::IsNullOrWhiteSpace($Matches[1])) {
                    $configuredRoots.Add($Matches[1])
                }
                continue
            }
            if ($line -match '^\s*(?:designlib_root|kb_root)\s*=\s*"((?:[^"\\]|\\.)*)"\s*(?:#.*)?$') {
                $value = $Matches[1].Replace('\\', '\').Replace('\"', '"')
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $configuredRoots.Add($value)
                }
            }
        }
    }

    return $configuredRoots
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
$currentCommonDirectory = Get-RepositoryCommonDirectory -RepositoryPath $currentRepository -LogicalName "Current repository"
$authorizedCommonDirectories = @(
    Get-RepositoryCommonDirectory -RepositoryPath $scriptRepository -LogicalName "Script repository"
)
foreach ($configuredRoot in Get-ConfiguredRepositoryRoots -ScriptRepository $scriptRepository) {
    $authorizedCommonDirectories += Get-RepositoryCommonDirectory `
        -RepositoryPath $configuredRoot `
        -LogicalName "Configured repository root"
}
$isAuthorizedRepository = $false
foreach ($authorizedCommonDirectory in $authorizedCommonDirectories) {
    if ($authorizedCommonDirectory.Equals($currentCommonDirectory, $pathComparison)) {
        $isAuthorizedRepository = $true
        break
    }
}
if (-not $isAuthorizedRepository) {
    throw "Run this controlled entrypoint from an authorized SoT repository worktree."
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
