$toolPath = Join-Path $HOME ".agents\ship-kb-tools\new-issue-bundle.ps1"
if (-not (Test-Path $toolPath)) {
    throw "Shared tool not found: $toolPath"
}
# The KB is the game repository's docs/ (two levels up); SOT_KB_ROOT is retired.
$kbRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
& $toolPath -KbRoot $kbRoot @args
