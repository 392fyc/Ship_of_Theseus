param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$PythonPath = "python"
)

$ErrorActionPreference = 'Stop'
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'claude_review/capture-gate.ps1')
Assert-CaptureProject $taskProject
$taskOutput = [IO.Path]::GetFullPath($OutputDirectory)
if (-not [IO.Path]::IsPathRooted($OutputDirectory) -or (Test-Path -LiteralPath $taskOutput)) {
    throw '请提供新的绝对输出目录。'
}
if ($taskOutput.StartsWith($taskProject.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $taskOutput -eq $taskProject) {
    throw '运行证据须保存在仓库外。'
}
$taskSources = @{}
$taskInputs = @(
    'scripts/ui/playground/courtyard_board_view.gd', 'scripts/ui/playground/terrain_painter.gd',
    'scripts/ui/terrain/terrain_catalog.gd', 'scripts/ui/terrain/terrain_surface.gd', 'scripts/ui/terrain/terrain_blend.gdshader',
    'assets/prototype/battlefield_courtyard/terrain_catalog.json', 'assets/prototype/battlefield_courtyard/terrain_examples.json',
    'assets/prototype/battlefield_courtyard/visual_profile.json', 'assets/prototype/battlefield_courtyard/water-depth-approved.json',
    'assets/prototype/battlefield_courtyard/natural-rock-v1.png', 'assets/prototype/battlefield_courtyard/water-surface-v5.png',
    'scenes/playground/terrain_painter.tscn', 'tests/test_terrain_kit.gd', 'tests/test_terrain_painter.gd',
    'tests/run_terrain_kit_validation.ps1'
)
foreach ($taskPath in $taskInputs) {
    $taskSources[$taskPath] = (Get-FileHash -LiteralPath (Join-Path $taskProject $taskPath) -Algorithm SHA256).Hash.ToLower()
}
$taskWater = Get-Content -LiteralPath (Join-Path $taskProject 'assets/prototype/battlefield_courtyard/water-depth-approved.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$taskBoard = (Get-Content -LiteralPath (Join-Path $taskProject 'scripts/ui/playground/courtyard_board_view.gd') -Raw -Encoding UTF8).Replace("`r`n", "`n")
foreach ($taskFunction in $taskWater.function_sha256.PSObject.Properties) {
    $taskMatch = [regex]::Match($taskBoard, '(?ms)^func ' + [regex]::Escape($taskFunction.Name) + '\(.*?(?=^func |\z)')
    $taskBytes = [Text.Encoding]::UTF8.GetBytes($taskMatch.Value.TrimEnd())
    $taskDigest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskBytes)).ToLower()
    if (-not $taskMatch.Success -or $taskDigest -cne $taskFunction.Value) { throw ('已批准的水深函数发生变化：' + $taskFunction.Name) }
}
$taskProfile = Get-Content -LiteralPath (Join-Path $taskProject 'assets/prototype/battlefield_courtyard/visual_profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($taskParameter in $taskWater.water_parameters.PSObject.Properties) {
    if ($taskProfile.water_surface.($taskParameter.Name) -cne $taskParameter.Value) { throw '已批准的水深参数发生变化。' }
}
if ($taskSources['assets/prototype/battlefield_courtyard/water-surface-v5.png'] -cne $taskWater.water_texture_sha256) { throw '已批准的水面纹理发生变化。' }
New-Item -ItemType Directory -Path $taskOutput | Out-Null
$taskReceipt = [ordered]@{ result = 'running'; water_baseline_unchanged = $true; sources_sha256 = $taskSources; steps = @() }
$taskReceiptFile = Join-Path $taskOutput 'terrain-validation-run.json'
try {
    & (Join-Path $PSScriptRoot 'run_courtyard_visual_validation.ps1') -GodotPath $GodotPath -PythonPath $PythonPath -OutputDirectory (Join-Path $taskOutput 'regression')
    $taskRegression = Get-Content -LiteralPath (Join-Path $taskOutput 'regression/validation-run.json') -Raw | ConvertFrom-Json
    if ($taskRegression.status -ne 'automated_evidence_complete_review_pending') { throw '原有战场回归未完成。' }
    foreach ($taskLogFile in Get-ChildItem -LiteralPath (Join-Path $taskOutput 'regression') -Filter '*.log' -File) {
        if ((Get-Content -LiteralPath $taskLogFile.FullName -Raw) -match '(?m)^(SCRIPT ERROR|ERROR:)') { throw ('运行日志存在引擎错误：' + $taskLogFile.Name) }
    }
    $taskReceipt.steps += @{ name = 'courtyard-regression'; result = 'pass'; count = 6 }
    foreach ($taskSpec in @(
        @{ name = 'kit'; script = 'test_terrain_kit.gd'; marker = 'TERRAIN_KIT_RESULT' },
        @{ name = 'painter'; script = 'test_terrain_painter.gd'; marker = 'TERRAIN_PAINTER_RESULT' }
    )) {
        $taskDirectory = Join-Path $taskOutput $taskSpec.name
        New-Item -ItemType Directory -Path $taskDirectory | Out-Null
        $taskLog = & $GodotPath --path $taskProject --rendering-method gl_compatibility --script ('res://tests/' + $taskSpec.script) -- ('--output=' + $taskDirectory) 2>&1
        $taskExit = $LASTEXITCODE
        $taskLog | Set-Content -LiteralPath (Join-Path $taskDirectory 'run.log') -Encoding UTF8
        if (($taskLog -join "`n") -match '(?m)^(SCRIPT ERROR|ERROR:)') { throw ('运行日志存在引擎错误：' + $taskSpec.name) }
        $taskLine = @($taskLog | ForEach-Object { [string]$_ } | Where-Object { $_.StartsWith($taskSpec.marker + ' ') })
        if ($taskExit -ne 0 -or $taskLine.Count -ne 1) { throw ('步骤失败或没有唯一结果：' + $taskSpec.name) }
        $taskResult = $taskLine[0].Substring($taskSpec.marker.Length + 1) | ConvertFrom-Json
        if ($taskSpec.name -eq 'kit') {
            if ($taskResult.result -cne 'pass' -or $taskResult.failures.Count -ne 0 -or $taskResult.allowed_distinct_pairs_rendered -ne 32 -or $taskResult.excluded_pairs -ne 4) { throw '地形组合验收未通过。' }
            if ($taskResult.captures.PSObject.Properties.Name.Count -ne 27) { throw '组合图和场景图缺失。' }
            foreach ($taskImage in $taskResult.captures.PSObject.Properties) {
                if ((Get-FileHash -LiteralPath (Join-Path $taskDirectory $taskImage.Name) -Algorithm SHA256).Hash -ine $taskImage.Value) { throw '图像摘要不符。' }
            }
        } else {
            if ($null -eq $taskResult.failed -or $taskResult.failed -ne 0 -or $taskResult.passed -lt 10) { throw '地图交互验收未通过。' }
            $taskComparison = Get-Content -LiteralPath (Join-Path $taskDirectory 'terrain-painter-comparison.json') -Raw | ConvertFrom-Json
            if ($taskComparison.same_map_data -isnot [bool] -or -not $taskComparison.same_map_data -or $taskComparison.same_pixels -isnot [bool] -or -not $taskComparison.same_pixels) { throw '手工与直接加载结果不一致。' }
            foreach ($taskKind in @('manual', 'json')) {
                $taskExpected = if ($taskKind -eq 'manual') { $taskComparison.manual_sha256 } else { $taskComparison.loaded_sha256 }
                if ((Get-FileHash -LiteralPath (Join-Path $taskDirectory ('terrain-painter-' + $taskKind + '.png')) -Algorithm SHA256).Hash -ine $taskExpected) { throw '工作台图像摘要不符。' }
            }
        }
        $taskReceipt.steps += @{ name = $taskSpec.name; result = 'pass'; evidence = $taskResult }
        Invoke-CaptureC8 -ProjectRoot $taskProject -PythonPath $PythonPath -Directory $taskDirectory -Name $taskSpec.name
    }
    foreach ($taskPath in $taskSources.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $taskProject $taskPath) -Algorithm SHA256).Hash -ine $taskSources[$taskPath]) { throw ('验收期间来源变化：' + $taskPath) }
    }
    $taskReceipt.result = 'pass'
} catch {
    $taskReceipt.result = 'fail'
    $taskReceipt.failure = $_.Exception.Message
    throw
} finally {
    $taskReceipt | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $taskReceiptFile -Encoding UTF8
}
Write-Output '地形库、拼块操作和原战场回归通过；用户视觉批准以批准记录为准。'
