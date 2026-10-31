[CmdletBinding(PositionalBinding = $false)]
param(
    # -DryRun still runs `git fetch origin` (to see current PR heads); it makes no other write.
    [switch]$DryRun,
    # Acknowledge that this branch is stacked on the open PR head branch(es) named here.
    [string[]]$StackedOn = @()
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
    foreach ($environmentName in @("SOT_DESIGNLIB_ROOT")) {
        $value = [Environment]::GetEnvironmentVariable($environmentName)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $configuredRoots.Add($value)
        }
    }

    $localRootsPath = Join-Path $ScriptRepository ".codex/project/sot-roots.local.toml"
    if (Test-Path -LiteralPath $localRootsPath -PathType Leaf) {
        $section = ""
        foreach ($line in Get-Content -LiteralPath $localRootsPath) {
            if ($line -match '^\s*\[') {
                $section = ""
                if ($line -cmatch '^\s*\[\s*roots\s*\]\s*(?:#.*)?$') {
                    $section = "roots"
                }
                continue
            }
            if ($section -ne "roots") {
                continue
            }
            if ($line -match "^\s*designlib_root\s*=\s*'([^']*)'\s*(?:#.*)?$") {
                if (-not [string]::IsNullOrWhiteSpace($Matches[1])) {
                    $configuredRoots.Add($Matches[1])
                }
                continue
            }
            if ($line -match '^\s*designlib_root\s*=\s*"((?:[^"\\]|\\.)*)"\s*(?:#.*)?$') {
                $value = $Matches[1].Replace('\\', '\').Replace('\"', '"')
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $configuredRoots.Add($value)
                }
            }
        }
    }

    return $configuredRoots
}

function Write-Diagnostic([string]$Message) {
    # Warnings go to stderr so stdout stays machine-readable.
    [Console]::Error.WriteLine("WARNING: $Message")
}
function Get-StackedPullRequests {
    param([Parameter(Mandatory = $true)][string]$CurrentBranch)

    $gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gh) {
        Write-Diagnostic "gh is not available; skipped the stacked pull request check."
        return @()
    }
    $json = & $gh.Source pr list --state open --limit 200 --json number,headRefName,baseRefName 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Diagnostic "gh could not list open pull requests (not signed in or no GitHub remote); skipped the stacked pull request check."
        return @()
    }
    try {
        $pullRequests = @(($json -join "`n") | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        Write-Diagnostic "gh returned unreadable pull request data; skipped the stacked pull request check."
        return @()
    }
    # Limitation: a lower PR that was rebased or force-pushed after this branch was cut can still go undetected.
    # Refresh remote-tracking refs so other lanes' heads are visible; failure only weakens the check.
    & git fetch --quiet origin 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Diagnostic "Could not fetch origin; the stacked pull request check may use stale refs." }

    $protectedRefs = @()
    foreach ($name in @("develop", "main", "master")) {
        & git rev-parse --verify --quiet "refs/remotes/origin/$name^{commit}" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $protectedRefs += "refs/remotes/origin/$name" }
    }
    $stacked = @()
    foreach ($pullRequest in $pullRequests) {
        $head = [string]$pullRequest.headRefName
        if (-not $head -or $head -eq $CurrentBranch) { continue }
        $headRef = "refs/remotes/origin/$head"
        & git rev-parse --verify --quiet "$headRef^{commit}" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { continue }
        # The fork point with the PR head covers a lower PR that advanced after this branch was cut.
        $mergeBase = (& git merge-base HEAD $headRef 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -ne 0 -or -not $mergeBase) { continue }
        $inProtected = $false
        foreach ($protectedRef in $protectedRefs) {
            & git merge-base --is-ancestor $mergeBase $protectedRef 2>$null
            if ($LASTEXITCODE -eq 0) { $inProtected = $true; break }
        }
        if (-not $inProtected) { $stacked += [pscustomobject]@{ Number = [int]$pullRequest.number; Head = $head } }
    }
    return $stacked
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
# Branches are named for their purpose; an agent or lane prefix is refused for a branch not yet on origin
# (Mercury #703, docs/02-Development/lane-collaboration.md section 6). A branch already published keeps its name.
if ($branch -match '^(claude|codex|lane)/') {
    # --exit-code: 0 the branch is on origin, 2 it is not, anything else means origin could not be read.
    $null = & git ls-remote --exit-code --heads origin "refs/heads/$branch" 2>$null
    $lsRemoteExit = $LASTEXITCODE
    if ($lsRemoteExit -eq 2) {
        throw "Branch '$branch' starts with an agent or lane prefix. Rename it to <type>/<purpose>[-<lane>]-<agent>, for example feature/zhufeng-review-gameplay-design-claude (git branch -m <new name>), then publish."
    }
    if ($lsRemoteExit -ne 0) {
        throw "Cannot check whether '$branch' is already on origin (git ls-remote exit code $lsRemoteExit); retry when origin is reachable. Do not rename a branch that is already published."
    }
}
$status = @(Invoke-Git -GitArgs @("status", "--porcelain"))
if ($status.Count -ne 0) {
    throw "Working tree is not clean. Commit changes before publishing."
}

$stackedPullRequests = @(Get-StackedPullRequests -CurrentBranch $branch)
$undeclared = @($stackedPullRequests | Where-Object { $StackedOn -notcontains $_.Head })
if ($undeclared.Count -ne 0) {
    $described = ($undeclared | ForEach-Object { "#$($_.Number) ($($_.Head))" }) -join ", "
    throw "Branch '$branch' contains commits from open pull request(s) $described that are not in a protected base branch, so it is stacked on them. Re-run with -StackedOn <head branch> to publish it as a stacked change, or rebase it onto the protected base."
}
foreach ($declared in $StackedOn) {
    if (@($stackedPullRequests | Where-Object { $_.Head -eq $declared }).Count -eq 0) {
        Write-Diagnostic "-StackedOn '$declared' matches no detected open pull request dependency of this branch."
    }
}
foreach ($dependency in $stackedPullRequests) {
    Write-Output "Stacked on open pull request #$($dependency.Number) ($($dependency.Head)). Put this in the PR description: Depends on #$($dependency.Number); merge after it."
}

if ($DryRun) {
    Write-Output "Dry-run: current task branch '$branch' would be published to origin with the same name."
    exit 0
}

$refspec = "HEAD:refs/heads/$branch"
$null = Invoke-Git -GitArgs @("push", "--porcelain", "origin", $refspec)
Write-Output "Published current task branch '$branch' to origin with the same name."
