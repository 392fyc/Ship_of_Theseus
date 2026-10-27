#requires -Version 7.0
# Version-conditioned active memory: verify, write, and record file hashes in <memory_root>/index.jsonl.
# Shared files: read -> remember the sha256 -> -Action Write -ExpectedSha256 <that hash> (compare-and-swap).
# Exit codes: 0 ok; 1 mismatch/refused (Verify, Write) or any mismatch/missing entry (Status); 2 missing file (Verify);
#   3 file written but index update failed (Write; register it with -Action Record).
# Platform: the cross-process index lock relies on Windows FileShare.None semantics; only Windows is supported.
# Layout: <memory_root>/projects/<bucket>/<relative path>; <memory_root>/index.jsonl rows point into it.
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)][ValidateSet('Verify','Record','Write','Status')][string]$Action,
    [string]$Path,
    [string]$ExpectedSha256,
    [string]$SourceFile,
    [switch]$CreateNew,
    [string]$Bucket,
    [string]$RootsFile = (Join-Path $PSScriptRoot '../../.codex/project/sot-roots.local.toml'),
    # Test mode: read only -RootsFile; SOT_MEMORY_ROOT is ignored.
    [switch]$IgnoreEnvironment
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
foreach ($key in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE')) {
    if ([Environment]::GetEnvironmentVariable($key)) { throw "Unset inherited $key before using this helper." }
}
function Write-Diagnostic([string]$Message) {
    # Warnings go to stderr so stdout stays machine-readable.
    [Console]::Error.WriteLine("WARNING: $Message")
}
$comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
function Full-Path([string]$Value) {
    if (-not [IO.Path]::IsPathFullyQualified($Value)) { throw 'The memory root must be an absolute path.' }
    return [IO.Path]::GetFullPath($Value).TrimEnd('\','/')
}

# --- Memory root: SOT_MEMORY_ROOT, then [roots].memory_root, then the game repo's primary worktree/.sot/memory.
$fileRoot = $null
if (Test-Path -LiteralPath $RootsFile -PathType Leaf) {
    $section = ''
    foreach ($line in Get-Content -LiteralPath $RootsFile) {
        if ($line -match '^\s*\[') { $section = if ($line -cmatch '^\s*\[\s*roots\s*\]\s*(?:#.*)?$') { 'roots' } else { '' }; continue }
        if ($section -ne 'roots') { continue }
        if ($line -match "^\s*memory_root\s*=\s*'([^']*)'\s*(?:#.*)?$") { $fileRoot = $Matches[1] }
        elseif ($line -match '^\s*memory_root\s*=\s*"((?:[^"\\]|\\.)*)"\s*(?:#.*)?$') { $fileRoot = $Matches[1].Replace('\\','\').Replace('\"','"') }
        elseif ($line -match '^\s*memory_root\s*=') { throw 'Use a single quoted literal path or double quoted path in the roots file.' }
    }
}
$envRoot = if ($IgnoreEnvironment) { $null } else { [Environment]::GetEnvironmentVariable('SOT_MEMORY_ROOT') }
if ($PSBoundParameters.ContainsKey('RootsFile') -and -not [string]::IsNullOrWhiteSpace($envRoot)) {
    Write-Diagnostic '-RootsFile was given, but SOT_MEMORY_ROOT overrides roots.memory_root. Use -IgnoreEnvironment to read only the roots file.'
}

# The game repo is the repository that holds this script; its primary worktree is listed first.
$scriptRepository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$mainWorktree = $null
$listing = & $git -C $scriptRepository worktree list --porcelain 2>$null
if ($LASTEXITCODE -eq 0) {
    $first = @($listing) -join "`n"
    $block = ($first -split "`n`n")[0] -split "`n"
    if (-not ($block | Where-Object { $_ -eq 'bare' })) {
        $line = $block | Where-Object { $_.StartsWith('worktree ') } | Select-Object -First 1
        if ($line) { $mainWorktree = [IO.Path]::GetFullPath($line.Substring(9)).TrimEnd('\','/') }
    }
}
if (-not [string]::IsNullOrWhiteSpace($envRoot)) { $memoryRoot = Full-Path $envRoot; $rootSource = 'SOT_MEMORY_ROOT' }
elseif ($fileRoot) { $memoryRoot = Full-Path $fileRoot; $rootSource = 'roots.memory_root' }
elseif ($mainWorktree) { $memoryRoot = Join-Path $mainWorktree '.sot/memory'; $rootSource = 'primary-worktree' }
else { throw 'Cannot determine the active memory root: no configuration and no primary game worktree.' }
if (-not (Test-Path -LiteralPath $memoryRoot -PathType Container)) { throw "Active memory is missing at $memoryRoot; nothing is guessed or created." }

# --- Bucket: a fixed project name, so moving the checkout does not split the project's memory.
if (-not $Bucket) { $Bucket = 'Ship_of_Theseus' }
if ($Bucket -in @('.','..') -or $Bucket -match '[\\/:\x00-\x1f]') { throw 'Invalid bucket name.' }
# Real layout: <memory_root>/projects/<bucket>/..., with index relative_path relative to that directory.
$bucketDirectory = Join-Path (Join-Path $memoryRoot 'projects') $Bucket
# A retired bucket name is a file that says where its records went; refuse it instead of recreating the bucket.
if (Test-Path -LiteralPath $bucketDirectory -PathType Leaf) {
    throw "Bucket '$Bucket' was retired: $("$(Get-Content -LiteralPath $bucketDirectory -Raw)".Trim())"
}
$indexPath = Join-Path $memoryRoot 'index.jsonl'

function Assert-NoLink([string]$Full, [string]$Stop) {
    $cursor = $Full
    while ($cursor -and -not $cursor.Equals($Stop, $comparison)) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing a path that crosses a reparse point.' }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}
# Returns the normalized relative path and its absolute location, or throws.
function Resolve-InBucket([string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative)) { throw '-Path is required.' }
    $unified = $Relative.Replace('\','/')
    if ($unified.StartsWith('/') -or $unified -match '^[A-Za-z]:' -or [IO.Path]::IsPathRooted($Relative)) { throw 'The path must be relative to the bucket.' }
    $segments = $unified -split '/'
    if ($segments | Where-Object { $_ -in @('','.','..') -or $_ -match '[\x00-\x1f]' }) { throw 'The path must not contain empty, ".", or ".." segments.' }
    if ($IsWindows) {
        if ($segments | Where-Object { $_ -match '[:<>"|?*]' -or $_ -match '[. ]$' -or $_ -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)' }) {
            throw 'The path contains a Windows-invalid or device-reserved segment.'
        }
    }
    $full = [IO.Path]::GetFullPath((Join-Path $bucketDirectory ($segments -join [IO.Path]::DirectorySeparatorChar)))
    if (-not $full.StartsWith($bucketDirectory.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, $comparison)) { throw 'The path escapes the bucket.' }
    Assert-NoLink $full $memoryRoot
    return [pscustomobject]@{ relative = ($segments -join '/'); full = $full }
}
function Get-Sha256([string]$Full) { return (Get-FileHash -LiteralPath $Full -Algorithm SHA256).Hash.ToLowerInvariant() }
function Json-String([string]$Value) {
    $sb = [Text.StringBuilder]::new('"')
    foreach ($c in $Value.ToCharArray()) {
        switch -CaseSensitive ($c) {
            '"' { [void]$sb.Append('\"') } '\' { [void]$sb.Append('\\') }
            default { if ([int]$c -lt 32) { [void]$sb.AppendFormat('\u{0:x4}', [int]$c) } else { [void]$sb.Append($c) } }
        }
    }
    return $sb.Append('"').ToString()
}
function Row-Json([string]$RelativePath, [string]$Sha, [long]$Size) {
    return '{"project_bucket":' + (Json-String $Bucket) + ',"relative_path":' + (Json-String $RelativePath) + ',"sha256":"' + $Sha + '","size_bytes":' + $Size + '}'
}
function Read-IndexLines {
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) { return @() }
    $text = [Text.UTF8Encoding]::new($false).GetString([IO.File]::ReadAllBytes($indexPath)).TrimStart([char]0xFEFF)
    if (-not $text) { return @() }
    $lines = @($text -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
    if ($lines.Count -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }
    return @($lines)
}
# Parses a line into its bucket entry, or $null for other buckets and unparsable lines.
function Parse-Entry([string]$Line) {
    if (-not $Line.Trim()) { return $null }
    try { $obj = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ($obj -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    foreach ($name in @('project_bucket','relative_path','sha256')) { if (-not ($obj.PSObject.Properties.Name -contains $name)) { return $null } }
    if ($obj.project_bucket -cne $Bucket) { return $null }
    return $obj
}
function Find-Row([string[]]$Lines, [string]$Relative) {
    if (-not $Lines) { return $null }
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $entry = Parse-Entry $Lines[$i]
        if ($entry -and ([string]$entry.relative_path).Equals($Relative, $comparison)) { return [pscustomobject]@{ index = $i; entry = $entry } }
    }
    return $null
}
function Check-File([string]$Relative, $Row) {
    $target = Resolve-InBucket $Relative
    $recorded = if ($Row) { ([string]$Row.entry.sha256).ToLowerInvariant() } else { $null }
    if (-not (Test-Path -LiteralPath $target.full -PathType Leaf)) { $state = 'missing'; $current = $null }
    else {
        $current = Get-Sha256 $target.full
        $state = if (-not $Row) { 'unrecorded' } elseif ($current -eq $recorded) { 'match' } else { 'mismatch' }
    }
    return [ordered]@{ path = $target.relative; result = $state; recorded_sha256 = $recorded; current_sha256 = $current }
}
function Open-IndexLock {
    # Serialize read-modify-write across processes with an exclusive lock file.
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        try { return [IO.FileStream]::new((Join-Path $memoryRoot 'index.jsonl.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 4096, [IO.FileOptions]::DeleteOnClose) }
        catch [IO.IOException], [UnauthorizedAccessException] { Start-Sleep -Milliseconds 100 }
    }
    throw 'Could not lock the memory index; another writer is active.'
}
function Move-Replace([string]$From, [string]$To, [int]$Attempts = 50) {
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        try { [IO.File]::Move($From, $To, $true); return } catch [IO.IOException], [UnauthorizedAccessException] { Start-Sleep -Milliseconds 50 }
    }
    Remove-Item -LiteralPath $From -Force
    throw "Could not replace $To."
}
# Caller holds the lock. Replaces only the target row (or appends it) and swaps the index atomically.
function Save-IndexRow([string[]]$Lines, $Row, [string]$Relative, [string]$Sha, [long]$Size) {
    $out = [Collections.Generic.List[string]]::new()
    foreach ($existing in $Lines) { $out.Add($existing) }
    $newLine = Row-Json $Relative $Sha $Size
    if ($Row) { $out[$Row.index] = $newLine } else { $out.Add($newLine) }
    $temporary = Join-Path $memoryRoot ('index.jsonl.' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllBytes($temporary, [Text.UTF8Encoding]::new($false).GetBytes((($out -join "`n") + "`n")))
    Move-Replace $temporary $indexPath 200
}
function Assert-Sha([string]$Value) {
    if ($Value -and $Value -notmatch '^[0-9a-fA-F]{64}$') { throw '-ExpectedSha256 must be a 64-digit hexadecimal SHA-256.' }
}
$context = [ordered]@{ memory_root = $memoryRoot; memory_root_source = $rootSource; bucket = $Bucket }

switch ($Action) {
    'Verify' {
        if (-not $Path) { throw '-Path is required.' }
        $target = Resolve-InBucket $Path
        $row = Find-Row @(Read-IndexLines) $target.relative
        $check = Check-File $target.relative $row
        if ($ExpectedSha256) {
            # Compare the disk content with the hash remembered at read time, not with the index.
            Assert-Sha $ExpectedSha256
            $check.expected_sha256 = $ExpectedSha256.ToLowerInvariant()
            if ($check.result -ne 'missing') { $check.result = if ($check.current_sha256 -eq $check.expected_sha256) { 'match' } else { 'mismatch' } }
        }
        ConvertTo-Json -InputObject ($context + $check + [ordered]@{ index_present = (Test-Path -LiteralPath $indexPath -PathType Leaf) })
        if ($check.result -eq 'mismatch') { exit 1 }
        if ($check.result -eq 'missing') { exit 2 }
    }
    'Status' {
        $rows = @()
        foreach ($line in @(Read-IndexLines)) {
            $entry = Parse-Entry $line
            if (-not $entry) { continue }
            try { $rows += [pscustomobject](Check-File ([string]$entry.relative_path) ([pscustomobject]@{ entry = $entry })) }
            catch { $rows += [pscustomobject][ordered]@{ path = [string]$entry.relative_path; result = 'invalid-path'; recorded_sha256 = [string]$entry.sha256; current_sha256 = $null } }
        }
        $bad = @($rows | Where-Object { $_.result -in @('mismatch','missing','invalid-path') }).Count
        ConvertTo-Json -InputObject ($context + [ordered]@{ index_present = (Test-Path -LiteralPath $indexPath -PathType Leaf); entries = $rows; problems = $bad }) -Depth 4
        if ($bad) { exit 1 }
    }
    'Record' {
        # Registers a file written by other means. Shared files should be changed with -Action Write instead,
        # because Record cannot detect a concurrent write that was already registered before this call.
        if (-not $Path) { throw '-Path is required.' }
        $target = Resolve-InBucket $Path
        if (-not (Test-Path -LiteralPath $target.full -PathType Leaf)) { throw 'Record requires the written file to exist.' }
        Assert-Sha $ExpectedSha256
        $lock = Open-IndexLock
        try {
            $lines = @(Read-IndexLines)
            $row = Find-Row $lines $target.relative
            if ($ExpectedSha256) {
                $recorded = if ($row) { ([string]$row.entry.sha256).ToLowerInvariant() } else { $null }
                if ($recorded -ne $ExpectedSha256.ToLowerInvariant()) {
                    throw "Concurrent write suspected: the index records '$recorded' for this path, not the expected hash. Re-read the file and merge before recording (omit -ExpectedSha256 for a path with no index row)."
                }
            }
            $sha = Get-Sha256 $target.full
            $size = (Get-Item -LiteralPath $target.full).Length
            Save-IndexRow $lines $row $target.relative $sha $size
        } finally { $lock.Dispose() }
        ConvertTo-Json -InputObject ($context + [ordered]@{ result = if ($row) { 'updated' } else { 'added' }; path = $target.relative; sha256 = $sha; size_bytes = $size; note = 'Record registers an existing file; use -Action Write for shared files so concurrent writes are detected.' })
    }
    'Write' {
        # Compare-and-swap on the disk content: recompute the hash, compare, replace atomically, update the index row.
        if (-not $Path) { throw '-Path is required.' }
        if (-not $SourceFile -or -not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) { throw '-SourceFile must name an existing file with the new content.' }
        Assert-Sha $ExpectedSha256
        if ($CreateNew -and $ExpectedSha256) { throw '-CreateNew cannot be combined with -ExpectedSha256.' }
        if (-not $CreateNew -and -not $ExpectedSha256) { throw 'Write requires -ExpectedSha256 (the hash read before editing) or -CreateNew for a new file.' }
        $target = Resolve-InBucket $Path
        $lock = Open-IndexLock
        $refusal = $null
        $indexError = $null
        try {
            # Re-check inside the lock and before anything is read or created.
            Assert-NoLink $target.full $memoryRoot
            $exists = Test-Path -LiteralPath $target.full -PathType Leaf
            if (Test-Path -LiteralPath $target.full -PathType Container) { throw 'The target is a directory.' }
            $disk = if ($exists) { Get-Sha256 $target.full } else { $null }
            if ($CreateNew -and $exists) { $refusal = 'exists' }
            elseif (-not $CreateNew -and $disk -ne $ExpectedSha256.ToLowerInvariant()) { $refusal = if ($exists) { 'mismatch' } else { 'missing' } }
            if (-not $refusal) {
                $directory = [IO.Path]::GetDirectoryName($target.full)
                if (-not (Test-Path -LiteralPath $directory)) { $null = New-Item -ItemType Directory -Path $directory -Force }
                $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($target.full) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
                Copy-Item -LiteralPath $SourceFile -Destination $temporary
                $sha = Get-Sha256 $temporary
                $size = (Get-Item -LiteralPath $temporary).Length
                Move-Replace $temporary $target.full
                try {
                    $lines = @(Read-IndexLines)
                    Save-IndexRow $lines (Find-Row $lines $target.relative) $target.relative $sha $size
                } catch { $indexError = "$_" }
            }
        } finally { $lock.Dispose() }
        if ($indexError) {
            ConvertTo-Json -InputObject ($context + [ordered]@{ status = 'written-index-stale'; result = 'written-index-stale'; path = $target.relative; sha256 = $sha; size_bytes = $size; note = 'The file was replaced but the index row was not updated. Run -Action Record for this path to register it.' })
            exit 3
        }
        if ($refusal) {
            ConvertTo-Json -InputObject ($context + [ordered]@{ result = "refused-$refusal"; path = $target.relative; current_sha256 = $disk; expected_sha256 = $ExpectedSha256; note = 'Nothing was written. Re-read the file, merge, and retry with the new hash.' })
            exit 1
        }
        ConvertTo-Json -InputObject ($context + [ordered]@{ result = if ($CreateNew) { 'created' } else { 'written' }; path = $target.relative; sha256 = $sha; size_bytes = $size })
    }
}
