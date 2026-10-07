#requires -Version 7.0
param(
    [Parameter(Mandatory = $true)][string] $GodotPath,
    [Parameter(Mandatory = $true)][string] $TemplateArchivePath,
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [switch] $CaptureVisual,
    [ValidateSet('kensei', 'myrmidon')][string] $PreviewClass = 'kensei',
    [string] $PythonPath = 'python'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Build([bool] $condition, [string] $message) {
    if (-not $condition) { throw $message }
}

function Assert-CR10FontAssets([string] $root) {
    $cjkDirectory = Join-Path $root 'assets/fonts/noto_sans_cjk_sc'
    $cjkManifestPath = Join-Path $cjkDirectory 'source.json'
    $cjkManifest = Get-Content -LiteralPath $cjkManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $cjkFontPath = Join-Path $cjkDirectory $cjkManifest.subset.font_file
    $cjkLicensePath = Join-Path $cjkDirectory $cjkManifest.upstream.license_file
    Assert-Build (Test-Path -LiteralPath $cjkFontPath -PathType Leaf) 'CR-10 字体子集缺失。'
    Assert-Build (Test-Path -LiteralPath $cjkLicensePath -PathType Leaf) 'CR-10 字体许可证缺失。'
    Assert-Build ((Get-FileHash -LiteralPath $cjkFontPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $cjkManifest.subset.font_sha256) 'CR-10 字体摘要与 source.json 不匹配。'
    Assert-Build ((Get-FileHash -LiteralPath $cjkLicensePath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $cjkManifest.upstream.license_sha256) 'CR-10 字体许可证摘要与 source.json 不匹配。'

    $symbolsDirectory = Join-Path $root 'assets/fonts/noto_sans_symbols'
    $symbolsManifestPath = Join-Path $symbolsDirectory 'source.json'
    $symbolsManifest = Get-Content -LiteralPath $symbolsManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $symbolsLicensePath = Join-Path $symbolsDirectory $symbolsManifest.upstream.license_file
    Assert-Build (Test-Path -LiteralPath $symbolsLicensePath -PathType Leaf) 'CR-10 符号字体许可证缺失。'
    Assert-Build ((Get-FileHash -LiteralPath $symbolsLicensePath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $symbolsManifest.upstream.license_sha256) 'CR-10 符号字体许可证摘要与 source.json 不匹配。'
    $expectedSymbolsFonts = @('NotoSansSymbols2-Regular-subset.ttf', 'NotoSansSymbols-Regular-subset.ttf')
    Assert-Build ($symbolsManifest.fonts.Count -eq $expectedSymbolsFonts.Count) 'CR-10 符号字体来源清单数量不正确。'
    foreach ($expectedFontName in $expectedSymbolsFonts) {
        $fontRecords = @($symbolsManifest.fonts | Where-Object { $_.font_file -eq $expectedFontName })
        Assert-Build ($fontRecords.Count -eq 1) "CR-10 符号字体来源清单缺少唯一记录：$expectedFontName"
        $fontRecord = $fontRecords[0]
        $fontPath = Join-Path $symbolsDirectory $fontRecord.font_file
        Assert-Build (Test-Path -LiteralPath $fontPath -PathType Leaf) "CR-10 符号字体子集缺失：$($fontRecord.font_file)"
        Assert-Build ((Get-FileHash -LiteralPath $fontPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $fontRecord.font_sha256) "CR-10 符号字体摘要不匹配：$($fontRecord.font_file)"
    }

    $emojiDirectory = Join-Path $root 'assets/fonts/noto_emoji'
    $emojiManifestPath = Join-Path $emojiDirectory 'source.json'
    $emojiManifest = Get-Content -LiteralPath $emojiManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $emojiFontPath = Join-Path $emojiDirectory $emojiManifest.subset.font_file
    $emojiLicensePath = Join-Path $emojiDirectory $emojiManifest.upstream.license_file
    Assert-Build (Test-Path -LiteralPath $emojiFontPath -PathType Leaf) 'CR-10 emoji 字体子集缺失。'
    Assert-Build (Test-Path -LiteralPath $emojiLicensePath -PathType Leaf) 'CR-10 emoji 字体许可证缺失。'
    Assert-Build ((Get-FileHash -LiteralPath $emojiFontPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $emojiManifest.subset.font_sha256) 'CR-10 emoji 字体摘要与 source.json 不匹配。'
    Assert-Build ((Get-FileHash -LiteralPath $emojiLicensePath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $emojiManifest.upstream.license_sha256) 'CR-10 emoji 字体许可证摘要与 source.json 不匹配。'
}

function Assert-CR10FontImportSettings([string] $root) {
    $fontSourcePaths = @(
        'assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Regular-subset.otf',
        'assets/fonts/noto_sans_symbols/NotoSansSymbols2-Regular-subset.ttf',
        'assets/fonts/noto_sans_symbols/NotoSansSymbols-Regular-subset.ttf',
        'assets/fonts/noto_emoji/NotoEmoji-Regular-400-subset.ttf'
    )
    foreach ($fontSourcePath in $fontSourcePaths) {
        $importPath = Join-Path $root "$fontSourcePath.import"
        Assert-Build (Test-Path -LiteralPath $importPath -PathType Leaf) "缺少 CR-10 字体导入设置：$fontSourcePath.import"
        $importText = Get-Content -LiteralPath $importPath -Raw -Encoding UTF8
        $fallbackMatch = [regex]::Match($importText, '(?m)^allow_system_fallback=(true|false)\r?$')
        Assert-Build ($fallbackMatch.Success -and $fallbackMatch.Groups[1].Value -eq 'false') "CR-10 字体导入设置启用了系统字体回退：$fontSourcePath.import"
    }
}

function Invoke-Godot([string[]] $arguments, [string] $logPath) {
    & $godot @arguments 2>&1 | Set-Content -LiteralPath $logPath -Encoding utf8
    Assert-Build ($LASTEXITCODE -eq 0) "Godot 命令失败；请查看 $(Split-Path $logPath -Leaf)。"
    $errors = @(Get-Content -LiteralPath $logPath | Where-Object { $_ -match '^(SCRIPT )?ERROR:' })
    Assert-Build ($errors.Count -eq 0) "Godot 报告脚本或资源错误；请查看 $(Split-Path $logPath -Leaf)。"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repoRoot 'tests/claude_review/capture-gate.ps1')
Assert-CaptureProject $repoRoot
Assert-CR10FontAssets $repoRoot
$godot = (Resolve-Path -LiteralPath $GodotPath).Path
$templateArchive = (Resolve-Path -LiteralPath $TemplateArchivePath).Path
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
Assert-Build ([IO.Path]::IsPathFullyQualified($OutputDirectory)) '输出目录必须使用绝对路径。'
Assert-Build (-not (Test-Path -LiteralPath $outputRoot)) '输出目录已存在；请另选新目录，以免覆盖现有文件。'
Assert-Build (-not $outputRoot.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) '输出目录不得位于游戏仓内。'

$engineVersion = (& $godot --version | Select-Object -First 1).Trim()
Assert-Build ($engineVersion.StartsWith('4.6.3.stable.official')) '本构建配置要求 Godot 4.6.3 官方稳定版。'
$officialTemplateHash = '3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8'
$actualTemplateHash = (Get-FileHash -LiteralPath $templateArchive -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Build ($actualTemplateHash -eq $officialTemplateHash) '导出模板与 Godot 4.6.3 官方发布文件摘要不一致。'

$null = New-Item -ItemType Directory -Path $outputRoot
$stage = Join-Path $outputRoot 'stage'
$dist = Join-Path $outputRoot 'dist'
$logs = Join-Path $outputRoot 'logs'
$templateDir = Join-Path $outputRoot 'template'
foreach ($directory in @($stage, $dist, $logs, $templateDir)) {
    $null = New-Item -ItemType Directory -Path $directory
}

$templateExe = Join-Path $templateDir 'windows_release_x86_64.exe'
$templateZip = [IO.Compression.ZipFile]::OpenRead($templateArchive)
try {
    $templateEntry = $templateZip.GetEntry('templates/windows_release_x86_64.exe')
    Assert-Build ($null -ne $templateEntry -and $templateEntry.Length -gt 0) '官方模板包中没有 Windows x86_64 发行模板。'
    [IO.Compression.ZipFileExtensions]::ExtractToFile($templateEntry, $templateExe)
} finally {
    $templateZip.Dispose()
}

$sourceCommit = (& git -C $repoRoot rev-parse HEAD)
Assert-Build ($sourceCommit -match '^[0-9a-f]{40}$') '无法读取游戏仓提交。'
$sourceZip = Join-Path $outputRoot 'source-snapshot.zip'
& git -C $repoRoot archive --format=zip "--output=$sourceZip" HEAD project.godot assets data scenes scripts
Assert-Build ($LASTEXITCODE -eq 0) '无法从当前提交准备游戏资源。'
[IO.Compression.ZipFile]::ExtractToDirectory($sourceZip, $stage)
Assert-CR10FontAssets $stage

$projectPath = Join-Path $stage 'project.godot'
$projectText = [IO.File]::ReadAllText($projectPath)
$autoloadPattern = '(?m)^MCPGameBridge="res://addons/godot_mcp/game_bridge/mcp_game_bridge\.gd"\r?\n'
$pluginPattern = '(?m)^enabled=PackedStringArray\("res://addons/godot_mcp/plugin\.cfg"\)\r?\n'
$settingsPattern = '(?ms)^\[godot_mcp\]\r?\n.*?(?=^\[|\z)'
foreach ($pattern in @($autoloadPattern, $pluginPattern, $settingsPattern)) {
    Assert-Build ([regex]::Matches($projectText, $pattern).Count -eq 1) '发行副本的 Godot MCP 配置与预期不符。'
}
$projectText = [regex]::Replace($projectText, $autoloadPattern, '')
$projectText = [regex]::Replace($projectText, $pluginPattern, "enabled=PackedStringArray()`n")
$projectText = [regex]::Replace($projectText, $settingsPattern, '')
Assert-Build (-not $projectText.Contains('godot_mcp')) '发行副本仍引用 Godot MCP。'
if ($CaptureVisual) {
    Assert-Build (Test-Path -LiteralPath (Join-Path $stage 'scripts/codex/release_capture_probe.gd')) '当前提交缺少发行采集观察器。'
    $projectText = $projectText.Replace('[autoload]', "[autoload]`nSoTReleaseCaptureProbe=`"*res://scripts/codex/release_capture_probe.gd`"")
}
[IO.File]::WriteAllText($projectPath, $projectText, [Text.UTF8Encoding]::new($false))
Assert-CaptureProject $stage

$scenePath = Join-Path $stage 'scenes/tactical/TacticalScene.tscn'
$sceneText = [IO.File]::ReadAllText($scenePath)
$sceneScriptLine = 'script = ExtResource("3_scene_script")'
Assert-Build ([regex]::Matches($sceneText, [regex]::Escape($sceneScriptLine)).Count -eq 1) '无法定位战斗场景的调试界面设置。'
$newline = if ($sceneText.Contains("`r`n")) { "`r`n" } else { "`n" }
$sceneText = $sceneText.Replace($sceneScriptLine, $sceneScriptLine + $newline + 'debug_harness_enabled = false')
[IO.File]::WriteAllText($scenePath, $sceneText, [Text.UTF8Encoding]::new($false))

if ($PreviewClass -eq 'myrmidon') {
    # 只在发行副本中切换测试战斗的展示职业；仓库里的剑圣测试场景不变。
    $controllerPath = Join-Path $stage 'scripts/tactical/tactical_scene.gd'
    $controllerText = [IO.File]::ReadAllText($controllerPath)
    $kenseiSpawn = '{"class_id": "kensei", "pos": Vector2i(1, 2), "facing": &"SE"},'
    Assert-Build ($controllerText.Split($kenseiSpawn).Count -eq 2) '无法唯一定位测试战斗的剑圣出生配置。'
    $myrmidonSpawn = '{"class_id": "myrmidon", "pos": Vector2i(1, 2), "facing": &"SE"},'
    [IO.File]::WriteAllText($controllerPath, $controllerText.Replace($kenseiSpawn, $myrmidonSpawn), [Text.UTF8Encoding]::new($false))
}

$presetTemplate = [IO.File]::ReadAllText((Join-Path $repoRoot 'release/windows-export-preset.cfg.in'))
Assert-Build ($presetTemplate.Split('__RELEASE_TEMPLATE_PATH__').Count -eq 2) '导出预设模板缺少唯一模板路径占位符。'
$templateForGodot = $templateExe.Replace('\', '/')
Assert-Build ($templateForGodot -notmatch '["\r\n]') '模板路径不能包含引号或换行。'
$preset = $presetTemplate.Replace('__RELEASE_TEMPLATE_PATH__', $templateForGodot)
[IO.File]::WriteAllText((Join-Path $stage 'export_presets.cfg'), $preset, [Text.UTF8Encoding]::new($false))

Invoke-Godot @('--headless', '--editor', '--path', $stage, '--import', '--quit') (Join-Path $logs 'import.log')
Assert-CR10FontImportSettings $stage
if ($PreviewClass -eq 'myrmidon') {
    $previewCheck = Join-Path $stage 'myrmidon_preview_check.gd'
    Copy-Item -LiteralPath (Join-Path $repoRoot 'tests/test_myrmidon_qi_only.gd') -Destination $previewCheck
    try {
        Invoke-Godot @('--headless', '--path', $stage, '--script', 'res://myrmidon_preview_check.gd', '--', '--expect-main-preview') (Join-Path $logs 'myrmidon-preview-check.log')
        Assert-Build ((Get-Content -LiteralPath (Join-Path $logs 'myrmidon-preview-check.log') -Raw).Contains('MYRMIDON_QI_ONLY_RESULT failed=0')) '基础剑士正式场景检查没有通过。'
    } finally {
        Remove-Item -LiteralPath $previewCheck
    }
}
$exe = Join-Path $dist 'ShipOfTheseus.exe'
Invoke-Godot @('--headless', '--path', $stage, '--export-release', 'Windows Desktop Release', $exe) (Join-Path $logs 'export.log')
$pck = Join-Path $dist 'ShipOfTheseus.pck'
Assert-Build ((Test-Path -LiteralPath $exe -PathType Leaf) -and (Test-Path -LiteralPath $pck -PathType Leaf)) '导出结果缺少 EXE 或 PCK。'
Assert-Build ((Get-Item -LiteralPath $exe).Length -gt 0 -and (Get-Item -LiteralPath $pck).Length -gt 0) 'EXE 或 PCK 为空。'

$licenses = [ordered]@{
    'GODOT_LICENSE.txt' = 'release/licenses/godot/LICENSE.txt'
    'GODOT_COPYRIGHT.txt' = 'release/licenses/godot/COPYRIGHT.txt'
    'IBM_PLEX_MONO_LICENSE.txt' = 'assets/fonts/ibm_plex_mono/LICENSE.txt'
    'SOURCE_SANS_PRO_LICENSE.txt' = 'assets/fonts/source_sans_pro/LICENSE.txt'
    'NOTO_SANS_CJK_SC_LICENSE.txt' = 'assets/fonts/noto_sans_cjk_sc/LICENSE.txt'
    'NOTO_SANS_SYMBOLS_LICENSE.txt' = 'assets/fonts/noto_sans_symbols/LICENSE.txt'
    'NOTO_EMOJI_LICENSE.txt' = 'assets/fonts/noto_emoji/LICENSE.txt'
}
$licenseDirectory = Join-Path $dist 'licenses'
$null = New-Item -ItemType Directory -Path $licenseDirectory
foreach ($filename in $licenses.Keys) {
    $source = Join-Path $repoRoot $licenses[$filename]
    Assert-Build ((Test-Path -LiteralPath $source -PathType Leaf) -and (Get-Item -LiteralPath $source).Length -gt 0) "缺少许可说明：$filename"
    Copy-Item -LiteralPath $source -Destination (Join-Path $licenseDirectory $filename)
}

$resourceZip = Join-Path $outputRoot 'resource-audit.zip'
Invoke-Godot @('--headless', '--path', $stage, '--export-pack', 'Windows Desktop Release', $resourceZip) (Join-Path $logs 'pack.log')
$iconAuditText = & (Join-Path $repoRoot 'scripts/codex/verify-myrmidon-export.ps1') -ArchivePath $resourceZip
$iconAudit = ($iconAuditText -join "`n") | ConvertFrom-Json
Assert-Build ($iconAudit.result -eq 'pass') '五张图标的资源包检查未通过。'
$resourceArchive = [IO.Compression.ZipFile]::OpenRead($resourceZip)
try {
    $excludedAddon = @($resourceArchive.Entries | Where-Object { $_.FullName -like 'addons/godot_mcp/*' })
    Assert-Build ($excludedAddon.Count -eq 0) '发行资源包仍包含 Godot MCP 插件。'
    $previewCheckEntries = @($resourceArchive.Entries | Where-Object { $_.FullName -like '*myrmidon_preview_check*' })
    Assert-Build ($previewCheckEntries.Count -eq 0) '发行资源包包含临时验收脚本。'
    $fontSourcePaths = @(
        'assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Regular-subset.otf',
        'assets/fonts/noto_sans_symbols/NotoSansSymbols2-Regular-subset.ttf',
        'assets/fonts/noto_sans_symbols/NotoSansSymbols-Regular-subset.ttf',
        'assets/fonts/noto_emoji/NotoEmoji-Regular-400-subset.ttf'
    )
    foreach ($fontSourcePath in $fontSourcePaths) {
        $importPath = "$fontSourcePath.import"
        $importEntries = @($resourceArchive.Entries | Where-Object { $_.FullName -eq $importPath })
        Assert-Build ($importEntries.Count -eq 1 -and $importEntries[0].Length -gt 0) "Windows 资源包缺少 CR-10 字体导入映射：$importPath"
        $importStream = $importEntries[0].Open()
        try {
            $importBytes = [IO.MemoryStream]::new()
            try {
                $importStream.CopyTo($importBytes)
                $importText = [Text.Encoding]::UTF8.GetString($importBytes.ToArray())
            } finally {
                $importBytes.Dispose()
            }
        } finally {
            $importStream.Dispose()
        }
        $fontDataMatch = [regex]::Match($importText, '(?m)^path="res://([^"]+\.fontdata)"\r?$')
        Assert-Build $fontDataMatch.Success "无法读取 CR-10 字体导入资源路径：$importPath"
        $fontDataPath = $fontDataMatch.Groups[1].Value
        $fontDataEntries = @($resourceArchive.Entries | Where-Object { $_.FullName -eq $fontDataPath })
        Assert-Build ($fontDataEntries.Count -eq 1 -and $fontDataEntries[0].Length -gt 0) "Windows 资源包缺少 CR-10 导入字体数据：$fontDataPath"
    }
} finally {
    $resourceArchive.Dispose()
}

$packageName = if ($PreviewClass -eq 'myrmidon') { 'ShipOfTheseus-MyrmidonHUD-Windows-x86_64.zip' } else { 'ShipOfTheseus-Windows-x86_64.zip' }
$packageZip = Join-Path $outputRoot $packageName
[IO.Compression.ZipFile]::CreateFromDirectory($dist, $packageZip)
$unpacked = Join-Path $outputRoot 'unpacked'
$null = New-Item -ItemType Directory -Path $unpacked
[IO.Compression.ZipFile]::ExtractToDirectory($packageZip, $unpacked)
Assert-Build ((Test-Path -LiteralPath (Join-Path $unpacked 'ShipOfTheseus.exe')) -and (Test-Path -LiteralPath (Join-Path $unpacked 'ShipOfTheseus.pck'))) '压缩包解开后缺少 EXE 或 PCK。'
foreach ($filename in $licenses.Keys) {
    $unpackedLicense = Join-Path $unpacked "licenses/$filename"
    $sourceLicense = Join-Path $repoRoot $licenses[$filename]
    Assert-Build (Test-Path -LiteralPath $unpackedLicense -PathType Leaf) "压缩包解开后缺少许可说明：$filename"
    Assert-Build ((Get-FileHash -LiteralPath $unpackedLicense -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $sourceLicense -Algorithm SHA256).Hash) "压缩包中的许可说明与源文件不一致：$filename"
}
$smokeOut = Join-Path $logs 'smoke.stdout.log'
$smokeErr = Join-Path $logs 'smoke.stderr.log'
$process = Start-Process -FilePath (Join-Path $unpacked 'ShipOfTheseus.exe') -ArgumentList @('--headless', '--quit-after', '120') -WorkingDirectory $unpacked -WindowStyle Hidden -RedirectStandardOutput $smokeOut -RedirectStandardError $smokeErr -PassThru
if (-not $process.WaitForExit(30000)) {
    $process.Kill()
    throw 'Windows 游戏包在 30 秒内未完成启动检查。'
}
Assert-Build ($process.ExitCode -eq 0) 'Windows 游戏包启动检查失败。'
$smokeLines = @((Get-Content -LiteralPath $smokeOut) + (Get-Content -LiteralPath $smokeErr))
$smokeErrors = @($smokeLines | Where-Object { $_ -match '^(SCRIPT )?ERROR:' })
Assert-Build ($smokeErrors.Count -eq 0) 'Windows 游戏包启动日志包含错误。'
if ($PreviewClass -eq 'myrmidon') {
    Assert-Build (($smokeLines -join "`n").Contains('[TurnManager] Turn: 剑士 (player)')) '解压后的程序未进入基础剑士回合。'
}

$visualHashes = [ordered]@{}
$runtimeConfigurations = @()
if ($CaptureVisual) {
    $captureRecords = @()
    foreach ($captureSize in @(@(1280, 720), @(1920, 1080), @(2560, 1440))) {
        $captureWidth = $captureSize[0]
        $captureResolution = $captureSize -join 'x'
        $visualOut = Join-Path $logs ('visual-' + $captureWidth + '.stdout.log')
        $visualErr = Join-Path $logs ('visual-' + $captureWidth + '.stderr.log')
        $runtimeConfigPath = Join-Path $outputRoot ('release-runtime-config-' + $captureWidth + '.json')
        $captureStart = [Diagnostics.ProcessStartInfo]::new((Join-Path $unpacked 'ShipOfTheseus.exe'))
        $captureStart.WorkingDirectory = $unpacked
        $captureStart.UseShellExecute = $false
        $captureStart.CreateNoWindow = $true
        $captureStart.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $captureStart.RedirectStandardOutput = $true
        $captureStart.RedirectStandardError = $true
        foreach ($argument in @('--fixed-fps', '60', '--', ('--capture-config=' + $runtimeConfigPath), ('--capture-size=' + $captureResolution), ('--capture-directory=' + $outputRoot))) {
            $captureStart.ArgumentList.Add($argument)
        }
        $visualProcess = [Diagnostics.Process]::Start($captureStart)
        $stdoutTask = $visualProcess.StandardOutput.ReadToEndAsync()
        $stderrTask = $visualProcess.StandardError.ReadToEndAsync()
        if (-not $visualProcess.WaitForExit(30000)) {
            $visualProcess.Kill()
            $visualProcess.WaitForExit()
            $visualProcess.Dispose()
            throw 'Windows 游戏包在 30 秒内未完成画面捕获。'
        }
        [IO.File]::WriteAllText($visualOut, $stdoutTask.GetAwaiter().GetResult())
        [IO.File]::WriteAllText($visualErr, $stderrTask.GetAwaiter().GetResult())
        $visualExitCode = $visualProcess.ExitCode
        $visualProcess.Dispose()
        Assert-Build ($visualExitCode -eq 0) 'Windows 游戏包画面捕获失败。'
        $frames = @(Get-ChildItem -LiteralPath $outputRoot -Filter ('hud-preview-' + $captureWidth + '-frame*.png') -File | Sort-Object Name)
        Assert-Build ($frames.Count -eq 10) 'Windows 游戏包没有生成预期的十帧画面。'
        $preview = Join-Path $outputRoot ('hud-preview-' + $captureWidth + '.png')
        Add-Type -AssemblyName System.Drawing
        $bitmap = [Drawing.Bitmap]::new($frames[-1].FullName)
        try {
            $bitmap.Save($preview, [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $bitmap.Dispose()
        }
        $visualHash = (Get-FileHash -LiteralPath $preview -Algorithm SHA256).Hash.ToLowerInvariant()
        $visualHashes[[string]$captureWidth] = $visualHash
        $visualLines = @((Get-Content -LiteralPath $visualOut) + (Get-Content -LiteralPath $visualErr))
        Assert-Build (@($visualLines | Where-Object { $_ -match '^(SCRIPT )?ERROR:' }).Count -eq 0) '发行采集运行出现引擎错误。'
        Assert-Build (Test-Path -LiteralPath $runtimeConfigPath) '缺少发行采集实测配置。'
        $runtime = Get-Content -LiteralPath $runtimeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Build ($runtime.frames.Count -eq $frames.Count) '实测配置帧数与实际图片帧数不同。'
        $runtimeConfigurations += [IO.Path]::GetFileName($runtimeConfigPath)
        for ($frameIndex = 0; $frameIndex -lt $frames.Count; $frameIndex++) {
            $frame = $frames[$frameIndex]
            $record = $runtime.frames[$frameIndex]
            $bitmap = [Drawing.Bitmap]::new($frame.FullName)
            try { $actualSize = @($bitmap.Width, $bitmap.Height) } finally { $bitmap.Dispose() }
            Assert-Build (($actualSize -join ',') -eq ($record.image_size -join ',')) '实测视口与发行帧尺寸不一致。'
            $record | Add-Member -NotePropertyName file -NotePropertyValue $frame.Name
            $record | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-FileHash -LiteralPath $frame.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $record | Add-Member -NotePropertyName capture_kind -NotePropertyValue 'viewport'
            $record | Add-Member -NotePropertyName capture_group -NotePropertyValue ('release-frame-' + $frameIndex)
            $captureRecords += $record
        }
        $previewRecord = $captureRecords[-1] | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $previewRecord.file = [IO.Path]::GetFileName($preview)
        $previewRecord.sha256 = $visualHash
        $previewRecord.capture_kind = 'derived_detail'
        $previewRecord | Add-Member -NotePropertyName source_file -NotePropertyValue $frames[-1].Name
        $previewRecord | Add-Member -NotePropertyName source_sha256 -NotePropertyValue $captureRecords[-1].sha256
        $previewRecord | Add-Member -NotePropertyName source_region -NotePropertyValue @(0, 0, $previewRecord.image_size[0], $previewRecord.image_size[1])
        $previewRecord | Add-Member -NotePropertyName scale -NotePropertyValue 1
        $captureRecords += $previewRecord
    }
    @{renderer=$runtime.frames[0].renderer; project_stretch_mode=$runtime.frames[0].project_stretch_mode; captures=$captureRecords} |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputRoot 'capture-metadata.json') -Encoding utf8
    Invoke-CaptureC8 -ProjectRoot $repoRoot -PythonPath $PythonPath -Directory $outputRoot -Name 'release'

}

$report = [ordered]@{
    status = 'pass'
    source_commit = $sourceCommit
    configured_renderer = 'gl_compatibility'
    capture_configuration = if ($CaptureVisual) { $runtimeConfigurations } else { $null }
    preview_class = $PreviewClass
    preview_audit_status = if ($PreviewClass -eq 'myrmidon') { 'pass' } else { 'not_applicable' }
    engine_version = $engineVersion
    template_archive_sha256 = $actualTemplateHash
    executable_sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    resource_pck_sha256 = (Get-FileHash -LiteralPath $pck -Algorithm SHA256).Hash.ToLowerInvariant()
    package_zip_sha256 = (Get-FileHash -LiteralPath $packageZip -Algorithm SHA256).Hash.ToLowerInvariant()
    package_zip_bytes = (Get-Item -LiteralPath $packageZip).Length
    icon_audit_sha256 = $iconAudit.archive_sha256
    icon_count = $iconAudit.runtime_assets.Count
    excluded_addon_entries = $excludedAddon.Count
    license_files = @($licenses.Keys)
    smoke_exit_code = $process.ExitCode
    visual_sha256 = $visualHashes
}
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputRoot 'release-build.json') -Encoding utf8
$report | ConvertTo-Json -Depth 4
