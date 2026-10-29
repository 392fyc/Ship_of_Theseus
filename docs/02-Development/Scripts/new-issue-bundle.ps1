$toolPath = Join-Path $HOME ".agents\ship-kb-tools\new-issue-bundle.ps1"
if (-not (Test-Path $toolPath)) {
    throw "Shared tool not found: $toolPath"
}
$kbRoot = if ($env:SOT_KB_ROOT) { $env:SOT_KB_ROOT } else { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..")) }
& $toolPath -KbRoot $kbRoot @args
