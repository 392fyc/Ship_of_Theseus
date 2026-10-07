#requires -Version 7.0
param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
Push-Location -LiteralPath $repoRoot
try {
if ($outputRoot.Equals($repoRoot, [StringComparison]::OrdinalIgnoreCase) -or $outputRoot.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '输出目录必须位于仓库外。' }
if (Test-Path -LiteralPath $outputRoot) { throw '输出目录已存在；请使用新的批次目录，保留旧证据。' }
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$stage = Join-Path $outputRoot 'project'
$archive = Join-Path $outputRoot 'source.zip'
$base = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw '无法读取基线提交。' }
& git archive --format=zip --output=$archive HEAD
if ($LASTEXITCODE -ne 0) { throw '无法导出候选基线。' }
Expand-Archive -LiteralPath $archive -DestinationPath $stage
$changed = @(((& git ls-files -z --modified --others --exclude-standard) -join "`n").Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))
if ($LASTEXITCODE -ne 0) { throw '无法读取候选改动。' }
foreach ($relative in $changed) {
    $source = Join-Path $repoRoot $relative
    $target = Join-Path $stage $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "候选包含删除项，采集脚本不自动处理：$relative" }
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force
    Copy-Item -LiteralPath $source -Destination $target
}
$sourcePaths = @(((& git ls-files -z --cached --others --exclude-standard) -join "`n").Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) | Sort-Object -Unique
if ($LASTEXITCODE -ne 0) { throw '无法列出来源文件。' }
$sourceManifest = @()
foreach ($relative in $sourcePaths) {
    $source = Join-Path $repoRoot $relative
    $target = Join-Path $stage $relative
    # Git archive 使用规范化换行；采集按当前工作树的逐文件原始字节冻结。
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "来源文件不存在：$relative" }
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force
    Copy-Item -LiteralPath $source -Destination $target
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sourceHash) { throw "来源复制不一致：$relative" }
    $sourceManifest += @{file=$relative; bytes=(Get-Item -LiteralPath $source).Length; sha256=$sourceHash}
}
@{schema='cr10-windows-source/1'; base_commit=$base; uncommitted_overlay=$changed; files=$sourceManifest} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputRoot 'source-manifest.json') -Encoding utf8
# 仅改变采集窗口的焦点属性；原 project.godot、拉伸、渲染器和场景不变。
if (Test-Path -LiteralPath (Join-Path $stage 'override.cfg')) { throw '来源已有 override.cfg，不能覆盖。' }
"[display]`nwindow/size/no_focus=true`n" | Set-Content -LiteralPath (Join-Path $stage 'override.cfg') -Encoding utf8

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SotFontCaptureForeground {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    public static uint ForegroundPid() { uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid; }
}
'@

function Invoke-CaptureProcess([string]$Name, [string[]]$ProcessArguments, [bool]$MonitorForeground) {
    $start = [Diagnostics.ProcessStartInfo]::new($GodotPath)
    $start.WorkingDirectory = $stage
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $ProcessArguments) { $start.ArgumentList.Add($argument) }
    $beforePid = [SotFontCaptureForeground]::ForegroundPid()
    $process = [Diagnostics.Process]::Start($start)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $samples = 0
    $foregroundSamples = 0
    $foregroundPids = [Collections.Generic.List[uint32]]::new()
    while (-not $process.HasExited) {
        if ($MonitorForeground) {
            $foregroundPids.Add([SotFontCaptureForeground]::ForegroundPid())
            $samples++
        }
        if ($clock.Elapsed.TotalSeconds -gt 180) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "$Name 超时，已停止本脚本启动的采集进程。"
        }
        Start-Sleep -Milliseconds 20
        $process.Refresh()
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $enginePid = $null
    if ($MonitorForeground) {
        # Godot console.exe 会启动真正持有窗口的 win64.exe；核对引擎原生 PID。
        $pidMatch = [regex]::Match($stdout, '(?m)^CR10_WINDOWS_PROCESS_ID\s+(\d+)\s*$')
        if ($pidMatch.Success) { $enginePid = [uint32]$pidMatch.Groups[1].Value }
        $foregroundSamples = @($foregroundPids | Where-Object { $_ -eq $process.Id -or $_ -eq $enginePid }).Count
    }
    [IO.File]::WriteAllText((Join-Path $outputRoot "$Name.stdout.log"), $stdout)
    [IO.File]::WriteAllText((Join-Path $outputRoot "$Name.stderr.log"), $stderr)
    $record = @{name=$Name; arguments=$ProcessArguments; exit_code=$process.ExitCode; elapsed_seconds=$clock.Elapsed.TotalSeconds;
        foreground_monitor=$MonitorForeground; samples=$samples; foreground_samples=$foregroundSamples;
        engine_process_id=$enginePid; launcher_process_id=$process.Id;
        before_after_foreground_same=($beforePid -eq [SotFontCaptureForeground]::ForegroundPid());
        window_position=@(-12000,-12000); operating_system_mouse_calls=$false; renderer='gl_compatibility'}
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outputRoot "$Name.command.json") -Encoding utf8
    if ($process.ExitCode -ne 0 -or $stdout -match '(?m)^(?:SCRIPT )?ERROR:' -or $stderr -match '(?m)^(?:SCRIPT )?ERROR:') { throw "$Name 未通过，请检查完整 stdout/stderr。" }
    if ($MonitorForeground -and $null -eq $enginePid) { throw "$Name 缺少引擎进程身份，无法核对前台窗口。" }
    if ($foregroundSamples -ne 0) { throw "$Name 成为过前台窗口，停止后续采集。" }
    Write-Output "$Name PASS"
}

Invoke-CaptureProcess 'import' @('--headless','--path',$stage,'--editor','--import','--quit') $false
Invoke-CaptureProcess 'font-runtime' @('--headless','--path',$stage,'--script','res://tests/claude_review/cr10_font_runtime_check.gd') $false
foreach ($weight in @('Regular', 'Medium')) {
    $captures = Join-Path $outputRoot $weight.ToLowerInvariant()
    Invoke-CaptureProcess ('capture-' + $weight.ToLowerInvariant()) @('--path',$stage,'--script','res://tests/claude_review/capture_cr10_windows_weights.gd',
        '--position','-12000,-12000','--resolution','1280x720','--rendering-method','gl_compatibility','--audio-driver','Dummy','--fixed-fps','60',
        '--',('--output=' + $captures),('--weight=' + $weight)) $true
}
foreach ($record in $sourceManifest) {
    if ((Get-FileHash -LiteralPath (Join-Path $stage $record.file) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sha256) { throw "测试修改了来源文件：$($record.file)" }
}
@{source_files=$sourceManifest.Count; original_sources_unchanged=$true; override=@{file='override.cfg'; no_focus=$true};
    baseline=$base; body_comparison=@('Regular','Medium'); title='Bold'; resolutions=@('1280x720','1920x1080','2560x1440');
    windows_appearance='pending_image_review'; publication=$false} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outputRoot 'capture-run.json') -Encoding utf8
} finally {
    Pop-Location
}
