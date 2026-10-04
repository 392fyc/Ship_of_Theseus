#requires -Version 7.0
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('List','Create','Inspect')][string]$Action = 'List',
    [ValidateSet('all','ship','designlib','kb')][string]$Repository = 'all',
    [string]$Task,
    [Alias('Path')][string]$WorktreePath,
    [string]$Branch,
    [string]$BaseRef,
    [string]$RootsFile = (Join-Path $PSScriptRoot '../../.codex/project/sot-roots.local.toml')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
# Inherited Git repository overrides could defeat -C and inspect another checkout.
foreach ($key in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE')) {
    if ([Environment]::GetEnvironmentVariable($key)) { throw "Unset inherited $key before using this helper." }
}
function Invoke-RepoGit([string]$Root, [string[]]$Arguments) {
    $output = & $git --no-optional-locks -c core.fsmonitor=false -C $Root @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git $($Arguments[0]) failed (exit $LASTEXITCODE)." }
    return $output
}
function Full-Path([string]$Value) {
    if (-not [IO.Path]::IsPathFullyQualified($Value)) { throw 'Repository and worktree roots must be absolute paths.' }
    return [IO.Path]::GetFullPath($Value).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}
function Assert-NoLink([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Refusing to create through a reparse point.'
            }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}
# The portable roots schema uses one-line TOML literal/basic strings, not arbitrary TOML.
$settings = @{ roots = @{}; worktrees = @{} }
$section = ''
if (Test-Path -LiteralPath $RootsFile -PathType Leaf) {
    foreach ($line in Get-Content -LiteralPath $RootsFile) {
        if ($line -match '^\s*\[([^]]+)\]\s*(?:#.*)?$') { $section = $Matches[1]; continue }
        if ($section -notin @('roots','worktrees')) { continue }
        if ($line -match '^\s*(ship_root|designlib_root|kb_root|memory_root)\s*=\s*("(?:[^"\\]|\\.)*"|''[^'']*'')\s*(?:#.*)?$') {
            $key = $Matches[1]; $quoted = $Matches[2]
            if ($settings[$section].ContainsKey($key)) { throw "Duplicate $section.$key in roots configuration." }
            $settings[$section][$key] = if ($quoted.StartsWith('"')) { $quoted | ConvertFrom-Json } else { $quoted.Substring(1,$quoted.Length-2) }
        } elseif ($line -match '^\s*(ship_root|designlib_root|kb_root|memory_root)\s*=') {
            throw 'Use a single quoted literal path or double quoted path with forward slashes in the roots file.'
        }
    }
}
$environmentKeys = @{
    roots = @{ship_root='SOT_SHIP_ROOT'; designlib_root='SOT_DESIGNLIB_ROOT'; kb_root='SOT_KB_ROOT'; memory_root='SOT_MEMORY_ROOT'}
    worktrees = @{ship_root='SOT_SHIP_WORKTREE_ROOT'; designlib_root='SOT_DESIGNLIB_WORKTREE_ROOT'; kb_root='SOT_KB_WORKTREE_ROOT'}
}
foreach ($section in @('roots','worktrees')) {
    foreach ($key in $environmentKeys[$section].Keys) {
        $value = [Environment]::GetEnvironmentVariable($environmentKeys[$section][$key])
        if (-not [string]::IsNullOrWhiteSpace($value)) { $settings[$section][$key] = $value }
        if ($settings[$section].ContainsKey($key)) { $settings[$section][$key] = Full-Path $settings[$section][$key] }
    }
}
$names = @{ship='Ship_of_Theseus'; designlib='SoT-fyc-space'; kb='ShipOfTheseus-KB'}
# memory_root is optional: when absent, sessions use the game's primary Git worktree/.sot/memory.
$optionalKeys = @('roots.memory_root')
function Root-For([string]$Section, [string]$Repo) {
    $key = $Repo + '_root'
    if (-not $settings[$Section].ContainsKey($key)) { throw "Missing $Section.$key; configure roots rather than guessing from a parent directory." }
    return $settings[$Section][$key]
}
function Read-Worktrees([string]$Repo) {
    $root = Root-For 'roots' $Repo
    $actualRoot = (@(Invoke-RepoGit $root @('rev-parse','--show-toplevel')) -join '').Trim()
    if ((Full-Path $actualRoot) -ne $root) { throw 'Configured repository root is not its checkout root.' }
    $group = Root-For 'worktrees' $Repo
    $text = @(Invoke-RepoGit $root @('worktree','list','--porcelain','-z')) -join "`n"
    $first = $true
    foreach ($block in ($text -split "`0`0")) {
        if (-not $block.Trim("`0","`r","`n")) { continue }
        $row = [ordered]@{repository=$Repo; path=''; head=''; branch='detached'; locked=$false; prunable=$false; is_main=$false; grouped=$false}
        foreach ($line in ($block -split "`0")) {
            if ($line.StartsWith('worktree ')) { $row.path = Full-Path $line.Substring(9) }
            elseif ($line.StartsWith('HEAD ')) { $row.head = $line.Substring(5) }
            elseif ($line.StartsWith('branch ')) { $row.branch = $line.Substring(7) }
            elseif ($line -match '^locked(?: |$)') { $row.locked = $true }
            elseif ($line -match '^prunable(?: |$)') { $row.prunable = $true }
        }
        if ($first -and $row.path -ne $root) { throw "Configured roots must identify the main checkout, not a linked worktree." }
        $row.is_main = $first
        $first = $false
        $row.grouped = [IO.Path]::GetDirectoryName($row.path) -eq $group
        [pscustomobject]$row
    }
}
if ($Action -eq 'Create') {
    if ($WorktreePath) { throw 'Create uses the configured repository group and Task; Path is only an inspection filter.' }
    if ($Repository -in @('all','kb')) { throw 'Create supports ship/designlib. KB writes use the existing fixed vault and its task branch.' }
    if ($Task -notmatch '^[a-z0-9][a-z0-9._-]{0,79}$' -or $Task.EndsWith('.') -or $Task -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)') { throw 'Use a safe task directory name (letters, numbers, dot, underscore, hyphen).' }
    if (-not $Branch -or -not $BaseRef -or $Branch -match '^(-|refs/|@)' -or $Branch -in @('main','master','develop')) { throw 'Create requires an explicit new task Branch and BaseRef.' }
    $root = Root-For 'roots' $Repository; $group = Root-For 'worktrees' $Repository
    if ([IO.Path]::GetFileName($group) -ne $names[$Repository]) { throw 'Worktree group must end in the repository name.' }
    $existing = @(Read-Worktrees $Repository)
    $target = Full-Path (Join-Path $group $Task)
    if ((Test-Path -LiteralPath $target) -or $target -in $existing.path) { throw 'Task path already exists or is registered; inspect it instead.' }
    Assert-NoLink $target
    Invoke-RepoGit $root @('check-ref-format','--branch',$Branch) | Out-Null
    $commit = (@(Invoke-RepoGit $root @('rev-parse','--verify','--end-of-options',($BaseRef+'^{commit}'))) -join '').Trim()
    # Save the effective configuration, including environment overrides, for the next session.
    $configLines = @()
    foreach ($section in @('roots','worktrees')) {
        $configLines += '['+$section+']'
        foreach ($key in ($environmentKeys[$section].Keys | Sort-Object)) {
            if (-not $settings[$section].ContainsKey($key)) {
                if ("$section.$key" -in $optionalKeys) { continue }
                throw "Create requires the complete roots schema: $section.$key."
            }
            $value = $settings[$section][$key].Replace('\','/')
            if ($value.Contains("'") -or $value -match '[\r\n]') { throw 'Cannot serialize the configured path as a TOML literal string.' }
            $configLines += "$key = '$value'"
        }
        $configLines += ''
    }
    if (-not (Test-Path -LiteralPath $group)) { $null = New-Item -ItemType Directory -Path $group }
    Invoke-RepoGit $root @('worktree','add','-b',$Branch,'--',$target,$commit) | Out-Null
    try {
        $relative = '.codex/project/sot-roots.local.toml'
        $destination = Join-Path $target $relative
        Assert-NoLink $destination
        Invoke-RepoGit $target @('check-ignore','--quiet','--',$relative) | Out-Null
        if (Test-Path -LiteralPath $destination) { throw 'New worktree already contains a local roots file; it was not overwritten.' }
        $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force
        $stream = [IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($configLines -join "`n")+"`n"); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    } catch { throw "Worktree was created at $target; local roots setup failed. Preserve it and inspect the error: $_" }
    $Action = 'List'
}
$repositories = if ($Repository -eq 'all') { @('ship','designlib','kb') } else { @($Repository) }
$result = @()
foreach ($repo in $repositories) {
    foreach ($row in @(Read-Worktrees $repo)) {
        if ($WorktreePath -and $row.path -ne (Full-Path $WorktreePath)) { continue }
        if ($Task -and [IO.Path]::GetFileName($row.path) -ne $Task) { continue }
        if ($Action -eq 'Inspect') {
            $row | Add-Member -NotePropertyName status -NotePropertyValue @((@(Invoke-RepoGit $row.path @('status','--porcelain=v1','-z','--untracked-files=all')) -join "`n") -split "`0" | Where-Object { $_ })
            $row | Add-Member -NotePropertyName ignored -NotePropertyValue @((@(Invoke-RepoGit $row.path @('ls-files','--others','--ignored','--exclude-standard','-z')) -join "`n") -split "`0" | Where-Object { $_ })
            $row | Add-Member -NotePropertyName hidden_index_flags -NotePropertyValue @(Invoke-RepoGit $row.path @('ls-files','-v') | Where-Object { $_ -cmatch '^[a-zS] ' })
            if ($BaseRef) {
                $base = (@(Invoke-RepoGit $row.path @('rev-parse','--verify','--end-of-options',($BaseRef+'^{commit}'))) -join '').Trim()
                $row | Add-Member -NotePropertyName commits_ahead -NotePropertyValue ([int](@(Invoke-RepoGit $row.path @('rev-list','--count',($base+'..'+$row.head))) -join ''))
            }
        }
        $result += $row
    }
}
if (-not $result.Count) { throw 'No registered worktree matches the requested repository/task.' }
ConvertTo-Json -InputObject $result -Depth 6
