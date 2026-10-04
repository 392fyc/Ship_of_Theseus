#requires -Version 7.0
# Controlled sync: merge origin/<base> into the current task branch (merge only, never rebase).
# -DryRun still runs `git fetch origin <base>` (to predict against current refs); it makes no other write
# (merge-tree may add unreferenced objects to the object database).
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$BaseBranch,
    [switch]$DryRun,
    [switch]$Abort,
    [string]$RootsFile = (Join-Path $PSScriptRoot '../../.codex/project/sot-roots.local.toml'),
    # Test mode: authorize repositories from -RootsFile only, ignoring SOT_* environment variables.
    [switch]$IgnoreEnvironment
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
foreach ($key in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE')) {
    if ([Environment]::GetEnvironmentVariable($key)) { throw "Unset inherited $key before using this helper." }
}
if ($Abort -and $DryRun) { throw '-Abort and -DryRun cannot be combined.' }

# Runs git in $Root and returns code and output lines. Non-zero exits throw unless -Lenient.
function Invoke-Git([string]$Root, [string[]]$Arguments, [switch]$Lenient, [switch]$NoStderr) {
    $output = if ($NoStderr) { & $git -C $Root @Arguments 2>$null } else { & $git -C $Root @Arguments 2>&1 }
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $Lenient) { throw "Git $($Arguments[0]) failed (exit $code)." }
    return [pscustomobject]@{ code = $code; out = @($output | ForEach-Object { "$_" }) }
}
function Common-Dir([string]$Root, [string]$Label) {
    $r = Invoke-Git $Root @('rev-parse','--path-format=absolute','--git-common-dir') -Lenient
    if ($r.code -ne 0) { throw "Could not identify the $Label Git repository." }
    return (Resolve-Path -LiteralPath $r.out[0].Trim()).Path
}
function Write-Diagnostic([string]$Message) {
    [Console]::Error.WriteLine("WARNING: $Message")
}
function Read-RootsFile([string]$Path) {
    $found = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $found }
    $section = ''
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*\[') { $section = if ($line -cmatch '^\s*\[\s*roots\s*\]\s*(?:#.*)?$') { 'roots' } else { '' }; continue }
        if ($section -ne 'roots') { continue }
        if ($line -match "^\s*(designlib_root|kb_root)\s*=\s*'([^']*)'\s*(?:#.*)?$") { $found[$Matches[1]] = $Matches[2] }
        elseif ($line -match '^\s*(designlib_root|kb_root)\s*=\s*"((?:[^"\\]|\\.)*)"\s*(?:#.*)?$') { $found[$Matches[1]] = $Matches[2].Replace('\\','\').Replace('\"','"') }
    }
    return $found
}
$comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
function Same-Path([string]$A, [string]$B) {
    $trim = { param($p) [IO.Path]::GetFullPath($p).TrimEnd('\','/') }
    return (& $trim $A).Equals((& $trim $B), $comparison)
}

# Identify the current checkout and which SoT repository it belongs to.
$top = (Invoke-Git (Get-Location).Path @('rev-parse','--show-toplevel') -Lenient)
if ($top.code -ne 0) { throw 'Run sot-sync.ps1 from a Git working tree.' }
$current = (Resolve-Path -LiteralPath $top.out[0].Trim()).Path
$currentCommon = Common-Dir $current 'current'
$scriptRepository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$kind = $null
if ((Common-Dir $scriptRepository 'script').Equals($currentCommon, $comparison)) { $kind = 'ship' }
$configured = [ordered]@{}
$fileRoots = Read-RootsFile $RootsFile
foreach ($key in @('designlib_root','kb_root')) {
    $value = if ($IgnoreEnvironment) { $null } else { [Environment]::GetEnvironmentVariable('SOT_' + $key.ToUpperInvariant()) }
    if ($PSBoundParameters.ContainsKey('RootsFile') -and -not [string]::IsNullOrWhiteSpace($value)) {
        Write-Diagnostic ("-RootsFile was given, but SOT_" + $key.ToUpperInvariant() + " overrides or supplies its value. Use -IgnoreEnvironment to read only the roots file.")
    }
    if ([string]::IsNullOrWhiteSpace($value) -and $fileRoots.Contains($key)) { $value = $fileRoots[$key] }
    if (-not [string]::IsNullOrWhiteSpace($value)) { $configured[$key.Replace('_root','')] = $value }
}
if (-not $kind) {
    foreach ($name in $configured.Keys) {
        # A configured root that is invalid or unrelated to this checkout must not abort the check.
        try { $candidate = Common-Dir $configured[$name] "configured $name root" } catch { continue }
        if ($candidate.Equals($currentCommon, $comparison)) { $kind = $name; break }
    }
}
if (-not $kind) { throw 'Run this controlled entrypoint from an authorized SoT repository worktree.' }

# Branch and worktree guards.
$sym = Invoke-Git $current @('symbolic-ref','--quiet','--short','HEAD') -Lenient
if ($sym.code -ne 0 -or -not $sym.out[0].Trim()) { throw 'Detached HEAD cannot be synchronized. Check out the assigned task branch.' }
$branch = $sym.out[0].Trim()
$firstWorktree = $null
foreach ($line in (Invoke-Git $current @('worktree','list','--porcelain')).out) {
    if ($line.StartsWith('worktree ')) { $firstWorktree = $line.Substring(9); break }
}
$isMain = $firstWorktree -and (Same-Path $firstWorktree $current)
if ($kind -eq 'kb') {
    # Only the fixed vault (the configured kb_root main worktree) is allowed; task isolation there is the checked-out branch.
    if (-not ($isMain -and (Same-Path $configured['kb'] $current))) { throw 'Only the fixed KB vault (the configured kb_root checkout) can be synchronized; linked KB worktrees are refused.' }
} elseif ($isMain) { throw 'The main worktree cannot be synchronized; use a task worktree.' }
if ($branch.ToLowerInvariant() -in @('main','master','develop')) { throw "Branch '$branch' is protected; synchronize from a task branch." }
$mergeInProgress = (Invoke-Git $current @('rev-parse','-q','--verify','MERGE_HEAD') -Lenient).code -eq 0

if ($Abort) {
    if (-not $mergeInProgress) { throw 'No merge is in progress; nothing to abort.' }
    Invoke-Git $current @('merge','--abort') | Out-Null
    ConvertTo-Json -InputObject ([ordered]@{ status = 'aborted'; repository = $kind; branch = $branch; head = (Invoke-Git $current @('rev-parse','HEAD')).out[0] })
    return
}
if ($mergeInProgress) { throw 'A merge is already in progress. Resolve it and commit normally, or rerun with -Abort.' }

# Resolve the base branch.
$base = $BaseBranch
if (-not $base) {
    if ($kind -eq 'ship') { $base = 'develop' }
    else {
        $head = Invoke-Git $current @('symbolic-ref','--quiet','--short','refs/remotes/origin/HEAD') -Lenient
        if ($head.code -eq 0 -and $head.out[0].Trim() -match '^origin/(.+)$') { $base = $Matches[1] }
        else {
            $remote = Invoke-Git $current @('remote','show','origin') -Lenient
            $hit = if ($remote.code -eq 0) { $remote.out | Where-Object { $_ -match '^\s*HEAD branch:\s*(\S+)\s*$' } | Select-Object -First 1 }
            if ($hit -and $hit -match 'HEAD branch:\s*(\S+)' -and $Matches[1] -ne '(unknown)') { $base = $Matches[1] }
        }
        if (-not $base) { throw 'Cannot resolve the default branch of origin; pass -BaseBranch explicitly.' }
    }
}
Invoke-Git $current @('check-ref-format','--branch',$base) | Out-Null
if ($base -eq $branch) { throw 'The current branch is the base branch; nothing to synchronize.' }

# Dirty tree: reported in dry-run as well.
$dirty = @((Invoke-Git $current @('status','--porcelain=v1','--untracked-files=all')).out | Where-Object { $_ })
if ($dirty.Count -and -not $DryRun) { throw 'Working tree is not clean. Commit or set aside changes before synchronizing.' }

Invoke-Git $current @('fetch','--quiet','origin',"+refs/heads/${base}:refs/remotes/origin/${base}") | Out-Null
$remoteRef = "refs/remotes/origin/$base"
$counts = (Invoke-Git $current @('rev-list','--left-right','--count',"HEAD...$remoteRef")).out[0].Trim() -split '\s+'
$ahead = [int]$counts[0]; $behind = [int]$counts[1]
$result = [ordered]@{ repository = $kind; branch = $branch; base = "origin/$base"; ahead = $ahead; behind = $behind }

if ($DryRun) {
    $predicted = 'up-to-date'; $conflicts = @()
    if ($behind -gt 0) {
        $tree = Invoke-Git $current @('merge-tree','--write-tree','--name-only','--no-messages','HEAD',$remoteRef) -Lenient -NoStderr
        if ($tree.code -eq 0) { $predicted = 'clean' }
        elseif ($tree.code -eq 1) {
            $predicted = 'conflict'
            $conflicts = @($tree.out | Select-Object -Skip 1 | Where-Object { $_ })
        } else { throw "Git merge-tree failed (exit $($tree.code))." }
    }
    $result = [ordered]@{ status = 'dry-run' } + $result + [ordered]@{
        predicted = $predicted; conflict_files = $conflicts; clean = ($dirty.Count -eq 0); dirty_files = @($dirty)
    }
    ConvertTo-Json -InputObject $result -Depth 4
    if ($dirty.Count) { exit 1 }
    return
}

if ($behind -eq 0) {
    ConvertTo-Json -InputObject ([ordered]@{ status = 'up-to-date' } + $result + [ordered]@{ head = (Invoke-Git $current @('rev-parse','HEAD')).out[0] })
    return
}
$merge = Invoke-Git $current @('merge','--no-ff','--no-edit',$remoteRef) -Lenient
if ($merge.code -eq 0) {
    ConvertTo-Json -InputObject ([ordered]@{ status = 'merged' } + $result + [ordered]@{ head = (Invoke-Git $current @('rev-parse','HEAD')).out[0] })
    return
}
$conflicted = @((Invoke-Git $current @('diff','--name-only','--diff-filter=U')).out | Where-Object { $_ })
if ((Invoke-Git $current @('rev-parse','-q','--verify','MERGE_HEAD') -Lenient).code -eq 0 -and $conflicted.Count) {
    ConvertTo-Json -InputObject ([ordered]@{ status = 'conflict' } + $result + [ordered]@{
        conflict_files = $conflicted
        next = 'Resolve the files and finish with a normal commit, or rerun sot-sync.ps1 -Abort to leave the merge.'
    }) -Depth 4
    exit 2
}
throw "Git merge failed (exit $($merge.code)) without a resolvable conflict: $($merge.out -join ' ')"
