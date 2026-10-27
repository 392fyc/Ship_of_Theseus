#requires -Version 7.0
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('List','Create','Inspect','KbReturn')][string]$Action = 'List',
    [ValidateSet('all','ship','designlib','kb')][string]$Repository = 'all',
    [string]$Task,
    [Alias('Path')][string]$WorktreePath,
    [string]$Branch,
    [string]$BaseRef,
    [string]$RootsFile = (Join-Path $PSScriptRoot '../../.codex/project/sot-roots.local.toml'),
    # Test mode: read only -RootsFile; SOT_* environment overrides are ignored.
    [switch]$IgnoreEnvironment,
    # Create and KbReturn: validate everything and print the plan without writing anything.
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
# Inherited Git repository overrides could defeat -C and inspect another checkout.
foreach ($key in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE')) {
    if ([Environment]::GetEnvironmentVariable($key)) { throw "Unset inherited $key before using this helper." }
}
function Write-Diagnostic([string]$Message) {
    # Warnings go to stderr so stdout stays machine-readable.
    [Console]::Error.WriteLine("WARNING: $Message")
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
        } elseif ($section -eq 'roots' -and $line -match '^\s*mercury_root\s*=') {
            Write-Warning 'Ignoring retired roots.mercury_root; configure an explicit roots.memory_root if a different active-memory root is required.'
        } elseif ($line -match '^\s*(ship_root|designlib_root|kb_root|memory_root)\s*=') {
            throw 'Use a single quoted literal path or double quoted path with forward slashes in the roots file.'
        }
    }
}
$environmentKeys = @{
    roots = @{ship_root='SOT_SHIP_ROOT'; designlib_root='SOT_DESIGNLIB_ROOT'; kb_root='SOT_KB_ROOT'; memory_root='SOT_MEMORY_ROOT'}
    worktrees = @{ship_root='SOT_SHIP_WORKTREE_ROOT'; designlib_root='SOT_DESIGNLIB_WORKTREE_ROOT'; kb_root='SOT_KB_WORKTREE_ROOT'}
}
$overridingVariables = @()
foreach ($section in @('roots','worktrees')) {
    foreach ($key in $environmentKeys[$section].Keys) {
        $value = if ($IgnoreEnvironment) { $null } else { [Environment]::GetEnvironmentVariable($environmentKeys[$section][$key]) }
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $settings[$section][$key] = $value
            $overridingVariables += $environmentKeys[$section][$key]
        }
        if (-not $settings[$section].ContainsKey($key)) { continue }
        # The optional memory root is only consumed by Create; it must not break List/Inspect.
        if ("$section.$key" -eq 'roots.memory_root' -and $Action -ne 'Create') { continue }
        $settings[$section][$key] = Full-Path $settings[$section][$key]
    }
}
if ($PSBoundParameters.ContainsKey('RootsFile') -and $overridingVariables.Count) {
    Write-Diagnostic ("-RootsFile was given, but these environment variables override or supply its values: " + ($overridingVariables -join ', ') + ". Use -IgnoreEnvironment to read only the roots file.")
}
if ($DryRun -and $Action -notin @('Create','KbReturn')) { Write-Diagnostic '-DryRun only applies to -Action Create and KbReturn and is ignored.' }
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
if ($Action -eq 'KbReturn') {
    # After a KB pull request merges: put the fixed vault back on its protected default branch (fast-forward only) and
    # delete the merged task branch. Agents call this entry instead of switching the vault's branch themselves.
    if ($Repository -ne 'kb') { throw 'KbReturn needs -Repository kb.' }
    if ($WorktreePath -or $Task -or $Branch -or $BaseRef) { throw 'KbReturn takes no Path, Task, Branch or BaseRef; it works on the branch the vault has checked out.' }
    $root = Root-For 'roots' 'kb'
    if ((Full-Path ((@(Invoke-RepoGit $root @('rev-parse','--show-toplevel')) -join '').Trim())) -ne $root) { throw 'Configured kb_root is not the vault checkout root.' }
    $gitDir = (@(Invoke-RepoGit $root @('rev-parse','--absolute-git-dir')) -join '').Trim()
    $commonDir = (@(Invoke-RepoGit $root @('rev-parse','--path-format=absolute','--git-common-dir')) -join '').Trim()
    if ((Full-Path $gitDir) -ne (Full-Path $commonDir)) { throw 'Configured kb_root is a linked worktree, not the fixed vault checkout.' }
    $dirty = @((@(Invoke-RepoGit $root @('status','--porcelain=v1','-z','--untracked-files=all')) -join "`n") -split "`0" | Where-Object { $_ })
    if ($dirty.Count) { throw "The vault has $($dirty.Count) uncommitted or untracked path(s); commit or publish them first. Nothing was changed." }
    $current = (@(& $git -C $root symbolic-ref --quiet --short HEAD) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $current) { throw 'The vault is on a detached HEAD; check out the task branch or inspect it by hand.' }
    Invoke-RepoGit $root @('fetch','--prune','origin') | Out-Null
    $symref = @(Invoke-RepoGit $root @('ls-remote','--symref','origin','HEAD')) | Where-Object { $_ -match '^ref: refs/heads/(\S+)\s+HEAD$' } | Select-Object -First 1
    if (-not $symref) { throw 'Could not read the default branch of origin.' }
    $default = ([regex]::Match($symref, '^ref: refs/heads/(\S+)')).Groups[1].Value
    $remoteDefault = 'refs/remotes/origin/' + $default
    $tip = (@(Invoke-RepoGit $root @('rev-parse','HEAD')) -join '').Trim()
    $evidence = $null
    if ($current -cne $default) {
        # Protected and default branches are never deleted, so they are never treated as task branches.
        if ($current -cin @('main','master','develop')) { throw "The vault is on protected branch '$current', not a task branch; return it by hand. Nothing was changed." }
        # A merged pull request whose head is this tip and whose base is the default branch (squash or merge commit).
        $url = (@(Invoke-RepoGit $root @('remote','get-url','origin')) -join '').Trim()
        $slug = ([regex]::Match($url, 'github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$')).Groups[1].Value
        $gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($slug -and $gh) {
            $raw = @(& $gh.Source pr list --repo $slug --head $current --base $default --state merged --json number,headRefOid,baseRefName)
            if ($LASTEXITCODE -eq 0) {
                $pr = @(($raw -join "`n") | ConvertFrom-Json) | Where-Object { $_.headRefOid -eq $tip -and $_.baseRefName -eq $default } | Select-Object -First 1
                if ($pr) { $evidence = "merged pull request #$($pr.number) into $default has head $tip" }
            }
        }
        if (-not $evidence) {
            # Without a pull request: the tip must be in the default branch and the branch must have commits of its own
            # (its tip moved past the commit it was created at, by its reflog), so a fresh, unused branch is never taken for a merged one.
            & $git -C $root merge-base --is-ancestor $tip $remoteDefault
            $inDefault = $LASTEXITCODE -eq 0
            $log = @(& $git -C $root reflog show --format=%H ('refs/heads/' + $current) 2>$null)
            $own = $log.Count -gt 1 -and $tip -ne $log[-1]
            if ($inDefault -and $own) { $evidence = "tip is in origin/$default" }
        }
        if (-not $evidence) { throw "Branch '$current' has no merge evidence (no merged pull request into $default has its tip as head, and it has no commits of its own that are in origin/$default). Nothing was changed." }
    }
    # Check that the switch and the fast-forward can both succeed before doing either.
    $localDefault = 'refs/heads/' + $default
    & $git -C $root show-ref --verify --quiet $localDefault
    if ($LASTEXITCODE -eq 0) {
        & $git -C $root merge-base --is-ancestor $localDefault $remoteDefault
        if ($LASTEXITCODE -ne 0) { throw "Local '$default' has commits that origin/$default does not have, so it cannot be fast-forwarded; inspect it by hand. Nothing was changed." }
    }
    if ($current -cne $default) {
        $porcelain = (@(Invoke-RepoGit $root @('worktree','list','--porcelain','-z')) -join "`n") -split "`0`0"
        foreach ($block in $porcelain) {
            $lines = $block -split "`0"
            $path = $lines | Where-Object { $_.StartsWith('worktree ') } | Select-Object -First 1
            if ($path -and ($lines -contains ('branch ' + $localDefault)) -and (Full-Path $path.Substring(9)) -ne $root) {
                throw "Branch '$default' is checked out in another worktree; release it there first. Nothing was changed."
            }
        }
    }
    $plan = [ordered]@{ status = $(if ($DryRun) { 'dry-run' } else { 'returned' }); repository = 'kb'; default_branch = $default
        task_branch = $(if ($current -cne $default) { $current } else { $null }); task_tip = $tip; merge_evidence = $evidence }
    if (-not $DryRun) {
        if ($current -cne $default) { Invoke-RepoGit $root @('switch','--',$default) | Out-Null }
        Invoke-RepoGit $root @('merge','--ff-only',$remoteDefault) | Out-Null
        if ($current -cne $default) {
            # -d when Git can see the merge; -D only for the verified squash merge above.
            $flag = if ($evidence -like 'tip is in*') { '-d' } else { '-D' }
            Invoke-RepoGit $root @('branch',$flag,'--',$current) | Out-Null
        }
        $plan.head = (@(Invoke-RepoGit $root @('rev-parse','HEAD')) -join '').Trim()
    }
    ConvertTo-Json -InputObject $plan -Depth 4
    return
}
if ($Action -eq 'Create') {
    if ($WorktreePath) { throw 'Create uses the configured repository group and Task; Path is only an inspection filter.' }
    if ($Repository -in @('all','kb')) { throw 'Create supports ship/designlib. KB writes use the existing fixed vault and its task branch.' }
    if ($Task -notmatch '^[a-z0-9][a-z0-9._-]{0,79}$' -or $Task.EndsWith('.') -or $Task -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)') { throw 'Use a safe task directory name (letters, numbers, dot, underscore, hyphen).' }
    if (-not $Branch -or -not $BaseRef -or $Branch -match '^(-|refs/|@)' -or $Branch -in @('main','master','develop')) { throw 'Create requires an explicit new task Branch and BaseRef.' }
    $root = Root-For 'roots' $Repository; $group = Root-For 'worktrees' $Repository
    # Task trees live inside their repository at <root>/.worktrees, which must be git-ignored there.
    if ($group -ne (Full-Path (Join-Path $root '.worktrees'))) { throw 'Worktree group must be <repository root>/.worktrees.' }
    & $git -C $root check-ignore --quiet --no-index -- ('.worktrees/' + $Task)
    if ($LASTEXITCODE -ne 0) { throw "The repository must git-ignore /.worktrees/ before task trees are created inside it." }
    $existing = @(Read-Worktrees $Repository)
    $target = Full-Path (Join-Path $group $Task)
    if ((Test-Path -LiteralPath $target) -or $target -in $existing.path) { throw 'Task path already exists or is registered; inspect it instead.' }
    Assert-NoLink $target
    Invoke-RepoGit $root @('check-ref-format','--branch',$Branch) | Out-Null
    & $git -C $root show-ref --verify --quiet ('refs/heads/' + $Branch)
    if ($LASTEXITCODE -eq 0) { throw "Branch '$Branch' already exists; Create never reuses or overwrites a branch." }
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
    if ($DryRun) {
        # Plan only: no directory, branch, or file is created. The check that the local roots file is git-ignored needs the new tree and is skipped.
        ConvertTo-Json -InputObject ([ordered]@{
            status = 'dry-run'; repository = $Repository; task = $Task; path = $target; branch = $Branch
            base_ref = $BaseRef; base_commit = $commit
            local_roots_path = (Join-Path $target '.codex/project/sot-roots.local.toml')
            local_roots_content = (($configLines -join "`n") + "`n")
        }) -Depth 4
        return
    }
    if (-not (Test-Path -LiteralPath $group)) { $null = New-Item -ItemType Directory -Path $group }
    # Godot imports every folder under a project; .gdignore keeps task trees out of the main project.
    $gdignore = Join-Path $group '.gdignore'
    if ((Test-Path -LiteralPath (Join-Path $root 'project.godot')) -and -not (Test-Path -LiteralPath $gdignore)) { $null = New-Item -ItemType File -Path $gdignore }
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
