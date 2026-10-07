#requires -Version 7.0
param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$ExpectedCommit
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$expectedHead = $ExpectedCommit.ToLowerInvariant()
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$godotExe = [IO.Path]::GetFullPath($GodotPath)
if (-not (Test-Path -LiteralPath $godotExe -PathType Leaf)) { throw 'GodotPath 必须指向可执行文件。' }
Push-Location -LiteralPath $repoRoot
try {
    if ($outputRoot.Equals($repoRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $outputRoot.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw '输出目录必须位于仓库外。'
    }
    if (Test-Path -LiteralPath $outputRoot) { throw '输出目录已存在；请使用新的批次目录并保留旧证据。' }
    $base = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw '无法读取候选基线。' }
    if ($expectedHead -notmatch '^[0-9a-f]{40}$') { throw 'ExpectedCommit 必须是完整 40 位提交 SHA。' }
    if ($base -ne $expectedHead) { throw "HEAD 与任务基线不符：$base" }
    $branch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) { throw '无法读取当前分支名。' }

    $null = New-Item -ItemType Directory -Path $outputRoot
    $stage = Join-Path $outputRoot 'project'
    $archive = Join-Path $outputRoot 'source.zip'
    & git archive --format=zip --output=$archive HEAD
    if ($LASTEXITCODE -ne 0) { throw '无法导出冻结基线。' }
    Expand-Archive -LiteralPath $archive -DestinationPath $stage

    $changed = @(((& git ls-files -z --modified --others --exclude-standard) -join "`n").Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))
    if ($LASTEXITCODE -ne 0) { throw '无法读取工作树覆盖项。' }
    $sourcePaths = @(((& git ls-files -z --cached --others --exclude-standard) -join "`n").Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) | Sort-Object -Unique
    if ($LASTEXITCODE -ne 0) { throw '无法列出冻结来源文件。' }

    $sourceManifest = [Collections.Generic.List[object]]::new()
    foreach ($relative in $sourcePaths) {
        $source = Join-Path $repoRoot $relative
        $target = [IO.Path]::GetFullPath((Join-Path $stage $relative))
        if (-not $target.StartsWith([IO.Path]::GetFullPath($stage) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "来源路径越出冻结目录：$relative"
        }
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "候选来源文件缺失：$relative" }
        $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force
        Copy-Item -LiteralPath $source -Destination $target
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        $stageHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($stageHash -ne $sourceHash) { throw "冻结副本字节不一致：$relative" }
        $sourceManifest.Add(@{
            file = $relative
            bytes = (Get-Item -LiteralPath $source).Length
            sha256 = $sourceHash
            overlay = ($changed -contains $relative)
        })
    }
    $sourceManifest.ToArray() | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputRoot 'source-manifest.json') -Encoding utf8
    if (Test-Path -LiteralPath (Join-Path $stage 'override.cfg')) { throw '冻结来源已有 override.cfg，不能覆盖。' }
    "[display]`nwindow/size/no_focus=true`n" | Set-Content -LiteralPath (Join-Path $stage 'override.cfg') -Encoding utf8

    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SotCR06CaptureForeground {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    public static uint ForegroundPid() { uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid; }
}
'@

    function Invoke-CaptureProcess([string]$Name, [string[]]$ProcessArguments, [bool]$MonitorForeground) {
        $start = [Diagnostics.ProcessStartInfo]::new($godotExe)
        $start.WorkingDirectory = $stage
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($argument in $ProcessArguments) { $start.ArgumentList.Add($argument) }
        $beforePid = [SotCR06CaptureForeground]::ForegroundPid()
        $startedAt = [DateTime]::UtcNow
        $process = [Diagnostics.Process]::Start($start)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $samples = [Collections.Generic.List[object]]::new()
        $timedOut = $false
        while (-not $process.HasExited) {
            if ($MonitorForeground) {
                $samples.Add(@{
                    elapsed_ms = [Math]::Round($clock.Elapsed.TotalMilliseconds, 1)
                    foreground_pid = [SotCR06CaptureForeground]::ForegroundPid()
                })
            }
            if ($clock.Elapsed.TotalSeconds -gt 240) {
                $timedOut = $true
                $process.Kill($true)
                $process.WaitForExit()
                break
            }
            Start-Sleep -Milliseconds 20
            $process.Refresh()
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $endedAt = [DateTime]::UtcNow
        $clock.Stop()
        $stdoutPath = Join-Path $outputRoot "$Name.stdout.log"
        $stderrPath = Join-Path $outputRoot "$Name.stderr.log"
        [IO.File]::WriteAllText($stdoutPath, $stdout, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($stderrPath, $stderr, [Text.UTF8Encoding]::new($false))
        $enginePid = $null
        if ($MonitorForeground) {
            # Godot console.exe may launch a separate win64.exe which owns the off-screen window.
            $pidMatch = [regex]::Match($stdout, '(?m)^CR06_WINDOWS_PROCESS_ID\s+(\d+)\s*$')
            if ($pidMatch.Success) { $enginePid = [uint32]$pidMatch.Groups[1].Value }
        }
        $observedPids = @($samples | ForEach-Object { [uint32]$_.foreground_pid } | Sort-Object -Unique)
        $candidatePids = @([uint32]$process.Id)
        if ($null -ne $enginePid) { $candidatePids += [uint32]$enginePid }
        $foregroundTargetSamples = @($samples | Where-Object { $candidatePids -contains [uint32]$_.foreground_pid }).Count
        $afterPid = [SotCR06CaptureForeground]::ForegroundPid()
        $record = @{
            name = $Name
            executable = $godotExe
            arguments = $ProcessArguments
            launcher_process_id = $process.Id
            engine_process_id = $enginePid
            started_utc = $startedAt.ToString('o')
            ended_utc = $endedAt.ToString('o')
            exit_code = $process.ExitCode
            timed_out = $timedOut
            elapsed_seconds = [Math]::Round($clock.Elapsed.TotalSeconds, 3)
            foreground_monitor = $MonitorForeground
            foreground_sample_interval_ms = 20
            foreground_samples = $samples.ToArray()
            distinct_foreground_pids = $observedPids
            foreground_target_samples = $foregroundTargetSamples
            foreground_before_pid = $beforePid
            foreground_after_pid = $afterPid
            before_after_foreground_same = ($beforePid -eq $afterPid)
            stdout_file = [IO.Path]::GetFileName($stdoutPath)
            stdout_sha256 = (Get-FileHash -LiteralPath $stdoutPath -Algorithm SHA256).Hash.ToLowerInvariant()
            stderr_file = [IO.Path]::GetFileName($stderrPath)
            stderr_sha256 = (Get-FileHash -LiteralPath $stderrPath -Algorithm SHA256).Hash.ToLowerInvariant()
            window_position = @(-12000, -12000)
            operating_system_mouse_calls = $false
            renderer = 'gl_compatibility'
        }
        $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outputRoot "$Name.command.json") -Encoding utf8
        if ($timedOut) { throw "$Name 超时，已停止本脚本启动的采集进程；完整输出已保存。" }
        if ($process.ExitCode -ne 0 -or $stdout -match '(?m)^(?:SCRIPT )?ERROR:' -or $stderr -match '(?m)^(?:SCRIPT )?ERROR:') {
            throw "$Name 未通过，请查看完整 stdout/stderr 与 command.json。"
        }
        if ($MonitorForeground -and $null -eq $enginePid) { throw "$Name 缺少引擎进程身份，无法核对窗口前台状态。" }
        if ($foregroundTargetSamples -ne 0) { throw "$Name 曾成为前台窗口，停止本批次。" }
        Write-Output "$Name PASS"
    }

    Invoke-CaptureProcess 'import' @('--headless', '--path', $stage, '--editor', '--import', '--quit') $false
    Invoke-CaptureProcess 'headless-api' @('--headless', '--path', $stage, '--script', 'res://tests/claude_review/capture_cr06_overhead.gd', '--', '--headless-check', '--weight=Medium') $false
    $captures = Join-Path $outputRoot 'captures'
    $null = New-Item -ItemType Directory -Path $captures
    Invoke-CaptureProcess 'windows-overhead' @('--path', $stage, '--script', 'res://tests/claude_review/capture_cr06_overhead.gd',
        '--position', '-12000,-12000', '--resolution', '1280x720', '--rendering-method', 'gl_compatibility',
        '--audio-driver', 'Dummy', '--fixed-fps', '60', '--', ('--output=' + $captures), '--weight=Medium') $true

    foreach ($record in $sourceManifest) {
        $staged = Join-Path $stage $record.file
        if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sha256) {
            throw "采集运行修改了冻结来源文件：$($record.file)"
        }
    }
    $captureFiles = @()
    foreach ($file in Get-ChildItem -LiteralPath $captures -File | Sort-Object Name) {
        $captureFiles += @{
            file = $file.Name
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    @{
        schema = 'cr06-windows-overhead-run/1'
        baseline = $base
        branch = $branch
        source_file_count = $sourceManifest.Count
        overlay_files = @($sourceManifest | Where-Object { $_.overlay } | ForEach-Object { $_.file })
        original_sources_unchanged = $true
        renderer = 'gl_compatibility'
        font = @{body='Medium'; title='Bold'}
        resolutions = @('1280x720', '1920x1080', '2560x1440')
        capture_cases = @('adjacent-forecast-hidden', 'adjacent-forecast-visible', 'camera-pan-zoom-forecast-reshown')
        capture_files = $captureFiles
        no_focus = $true
        offscreen_window_position = @(-12000, -12000)
        input_origin = 'Viewport.push_input only'
        operating_system_mouse_calls = $false
        foreground_target_samples = 0
        publication = $false
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputRoot 'capture-run.json') -Encoding utf8
} finally {
    Pop-Location
}
