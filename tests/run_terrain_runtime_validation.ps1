param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskOutput = [IO.Path]::GetFullPath($OutputDirectory)
if (-not [IO.Path]::IsPathRooted($OutputDirectory) -or (Test-Path -LiteralPath $taskOutput)) {
    throw '请提供新的绝对输出目录。'
}
if ($taskOutput -eq $taskProject -or $taskOutput.StartsWith($taskProject.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '运行证据须保存在仓库外。'
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw '找不到 Godot 程序。' }

$taskApproval = Get-Content -LiteralPath (Join-Path $taskProject 'assets/prototype/battlefield_courtyard/terrain-kit-approved.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskApproval.approval_status -cne 'user_approved') { throw '缺少当前外观批准记录。' }
$taskCatalogPath = 'scripts/ui/terrain/terrain_catalog.gd'
$taskVisualScope = Get-Content -LiteralPath (Join-Path $taskProject 'assets/prototype/battlefield_courtyard/terrain-catalog-visual-scope.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskVisualScope.source -cne $taskCatalogPath -or
    $taskVisualScope.baseline_source_sha256 -cne $taskApproval.sources_sha256.$taskCatalogPath) {
    throw '地图尺寸改动未关联到原批准来源。'
}
# Catalog 同时负责输入校验和外观参数。用户已授权尺寸变化，外观部分仍须与原批准版一致。
$taskCatalogText = [IO.File]::ReadAllText((Join-Path $taskProject $taskCatalogPath)).Replace("`r`n", "`n")
$taskPathMatch = [regex]::Match($taskCatalogText, '(?m)^const PATH := "([^"]+)"$')
if (-not $taskPathMatch.Success -or $taskPathMatch.Groups[1].Value -cne $taskVisualScope.visual_data_path) {
    throw '地形外观数据来源发生变化。'
}
foreach ($taskFunctionName in @('catalog', 'pair_rule', 'transition_style')) {
    $taskFunction = [regex]::Match($taskCatalogText, ('(?ms)^static func ' + $taskFunctionName + '\(.*?(?=^static func |\z)'))
    if (-not $taskFunction.Success) { throw ('缺少批准的外观函数：' + $taskFunctionName) }
    $taskFunctionBytes = [Text.Encoding]::UTF8.GetBytes($taskFunction.Value.TrimEnd())
    $taskFunctionHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskFunctionBytes)).ToLower()
    if ($taskFunctionHash -cne $taskVisualScope.visual_function_sha256.$taskFunctionName) {
        throw ('已批准的外观函数发生变化：' + $taskFunctionName)
    }
}
$taskSources = @{}
foreach ($taskSource in $taskApproval.sources_sha256.PSObject.Properties) {
    $taskDigest = (Get-FileHash -LiteralPath (Join-Path $taskProject $taskSource.Name) -Algorithm SHA256).Hash.ToLower()
    if ($taskSource.Name -cne $taskCatalogPath -and $taskDigest -cne $taskSource.Value) { throw ('已批准的地形来源发生变化：' + $taskSource.Name) }
    $taskSources[$taskSource.Name] = $taskDigest
}
foreach ($taskPath in @(
    'scripts/core/tactical_manager.gd', 'scripts/tactical/tactical_scene.gd', 'scripts/units/unit.gd',
    'scripts/tactical/terrain_battle_session.gd', 'scripts/ui/terrain/terrain_battle_definition.gd',
    'scripts/ui/playground/battlefield_courtyard.gd', 'scripts/ui/playground/terrain_painter.gd',
    'data/battlefields/terrain_workshop_test.json', 'scenes/playground/terrain_painter.tscn',
    'tests/test_terrain_battle_runtime.gd', 'tests/test_terrain_painter_battle_flow.gd',
    'tests/test_terrain_map_size.gd', 'tests/test_terrain_painter.gd', 'tests/test_terrain_kit.gd',
    'tests/test_tactical_inject_smoke.gd', 'tests/run_terrain_runtime_validation.ps1',
    'assets/prototype/battlefield_courtyard/terrain-catalog-visual-scope.json',
    'assets/prototype/battlefield_courtyard/terrain-kit-approved.json'
)) {
    $taskSources[$taskPath] = (Get-FileHash -LiteralPath (Join-Path $taskProject $taskPath) -Algorithm SHA256).Hash.ToLower()
}
New-Item -ItemType Directory -Path $taskOutput | Out-Null
$taskReceipt = [ordered]@{ result = 'running'; approved_visual_files_unchanged = 27;
    approved_catalog_visual_functions_unchanged = 3; catalog_validation_scope_updated = $true;
    sources_sha256 = $taskSources; steps = @() }
try {
    foreach ($taskSpec in @(
        @{ name = 'map-size'; script = 'test_terrain_map_size.gd'; marker = 'TERRAIN_MAP_SIZE_RESULT' },
        @{ name = 'runtime'; script = 'test_terrain_battle_runtime.gd'; marker = 'TERRAIN_BATTLE_RUNTIME_RESULT' },
        @{ name = 'editor-flow'; script = 'test_terrain_painter_battle_flow.gd'; marker = 'TERRAIN_PAINTER_BATTLE_FLOW_RESULT' },
        @{ name = 'legacy-injection'; script = 'test_tactical_inject_smoke.gd'; marker = '' }
    )) {
        $taskDirectory = Join-Path $taskOutput $taskSpec.name
        New-Item -ItemType Directory -Path $taskDirectory | Out-Null
        $taskArguments = @('--path', $taskProject, '--script', ('res://tests/' + $taskSpec.script))
        if ($taskSpec.name -eq 'legacy-injection') { $taskArguments += '--headless' }
        else { $taskArguments += @('--rendering-method', 'gl_compatibility', '--', ('--output=' + $taskDirectory)) }
        $taskLog = & $GodotPath @taskArguments 2>&1
        $taskExit = $LASTEXITCODE
        $taskLog | Set-Content -LiteralPath (Join-Path $taskDirectory 'run.log') -Encoding UTF8
        $taskText = $taskLog -join "`n"
        if ($taskExit -ne 0 -or $taskText -match '(?m)^(SCRIPT ERROR|ERROR:)|ObjectDB instances leaked|resources still in use') {
            throw ('运行失败或存在引擎清理错误：' + $taskSpec.name)
        }
        if ($taskSpec.name -eq 'legacy-injection') {
            if ($taskText -notmatch '结果：(\d+) 过 / 0 失败' -or [int]$Matches[1] -lt 1) { throw '旧地图注入检查未明确通过。' }
            $taskReceipt.steps += @{ name = $taskSpec.name; result = 'pass'; checks = [int]$Matches[1] }
            continue
        }
        $taskLine = @($taskLog | ForEach-Object { [string]$_ } | Where-Object { $_.StartsWith($taskSpec.marker + ' ') })
        if ($taskLine.Count -ne 1) { throw ('缺少唯一结果：' + $taskSpec.name) }
        $taskResult = $taskLine[0].Substring($taskSpec.marker.Length + 1) | ConvertFrom-Json
        if ($taskSpec.name -eq 'map-size') {
            if ($taskResult.result -cne 'pass' -or $null -eq $taskResult.failures -or $taskResult.failures.Count -ne 0 -or
                $taskResult.checks -lt 79 -or $taskResult.min_side -ne 10 -or $taskResult.max_side -ne 25 -or
                $taskResult.square_only -isnot [bool] -or -not $taskResult.square_only -or
                $taskResult.captures.PSObject.Properties.Name.Count -ne 5) { throw '地图尺寸检查未通过。' }
            foreach ($taskImage in $taskResult.captures.PSObject.Properties) {
                if ((Get-FileHash -LiteralPath (Join-Path $taskDirectory $taskImage.Name) -Algorithm SHA256).Hash -ine $taskImage.Value) { throw '尺寸图像摘要不符。' }
            }
        } elseif ($taskSpec.name -eq 'runtime') {
            if ($taskResult.result -cne 'pass' -or $null -eq $taskResult.failures -or $taskResult.failures.Count -ne 0 -or
                $taskResult.checks -lt 89 -or $taskResult.global_maps_unchanged -isnot [bool] -or -not $taskResult.global_maps_unchanged -or
                $taskResult.captures.PSObject.Properties.Name.Count -ne 6) { throw '正式试战检查未通过。' }
            foreach ($taskImage in $taskResult.captures.PSObject.Properties) {
                if ((Get-FileHash -LiteralPath (Join-Path $taskDirectory $taskImage.Name) -Algorithm SHA256).Hash -ine $taskImage.Value) { throw '试战图像摘要不符。' }
            }
        } else {
            if ($null -eq $taskResult.failed -or $taskResult.failed -ne 0 -or $taskResult.passed -lt 19) { throw '工作台往返检查未通过。' }
            $taskFlow = Get-Content -LiteralPath (Join-Path $taskDirectory 'terrain-painter-battle-flow.json') -Raw | ConvertFrom-Json
            if ($taskFlow.failed -ne $taskResult.failed -or $taskFlow.passed -ne $taskResult.passed) { throw '工作台报告与运行结果不一致。' }
            foreach ($taskImage in @($taskFlow.battle_capture, $taskFlow.return_capture)) {
                if ([string]::IsNullOrEmpty($taskImage) -or -not (Test-Path -LiteralPath (Join-Path $taskDirectory $taskImage) -PathType Leaf)) { throw '工作台往返截图缺失。' }
            }
        }
        $taskReceipt.steps += @{ name = $taskSpec.name; result = 'pass'; evidence = $taskResult }
    }
    & (Join-Path $PSScriptRoot 'run_terrain_kit_validation.ps1') -GodotPath $GodotPath -OutputDirectory (Join-Path $taskOutput 'terrain-regression')
    $taskRegression = Get-Content -LiteralPath (Join-Path $taskOutput 'terrain-regression/terrain-validation-run.json') -Raw | ConvertFrom-Json
    if ($taskRegression.result -cne 'pass') { throw '地形与原场景回归失败。' }
    foreach ($taskLogFile in Get-ChildItem -LiteralPath $taskOutput -Recurse -Filter '*.log' -File) {
        if ((Get-Content -LiteralPath $taskLogFile.FullName -Raw) -match '(?m)^(SCRIPT ERROR|ERROR:)|ObjectDB instances leaked|resources still in use') {
            throw ('日志存在引擎错误：' + $taskLogFile.Name)
        }
    }
    $taskReceipt.steps += @{ name = 'terrain-regression'; result = 'pass'; evidence = 'terrain-regression/terrain-validation-run.json' }
    foreach ($taskPath in $taskSources.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $taskProject $taskPath) -Algorithm SHA256).Hash -ine $taskSources[$taskPath]) { throw ('验证期间来源变化：' + $taskPath) }
    }
    $taskReceipt.result = 'pass'
} catch {
    $taskReceipt.result = 'fail'
    $taskReceipt.failure = $_.Exception.Message
    throw
} finally {
    $taskReceipt | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath (Join-Path $taskOutput 'terrain-runtime-validation.json') -Encoding UTF8
}
Write-Output '地图尺寸、编辑、正式试战、返回与旧场景回归通过，已批准地形绘制内容不变。'
