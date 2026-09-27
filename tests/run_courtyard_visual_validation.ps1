param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskOutput = [IO.Path]::GetFullPath($OutputDirectory)
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { throw '输出目录必须是绝对路径。' }
if ($taskOutput.Equals($taskProject, [StringComparison]::OrdinalIgnoreCase) -or
    $taskOutput.StartsWith($taskProject.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '原始截图与运行日志应保存在仓库外。'
}
if (Test-Path -LiteralPath $taskOutput) { throw '请使用新的输出目录，避免混入另一轮证据。' }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw '找不到指定的 Godot 程序。' }
New-Item -ItemType Directory -Path $taskOutput | Out-Null

$taskSteps = @(
    @{ name = 'water-contract'; script = 'test_courtyard_water_visual_contract.gd'; headless = $false; marker = 'COURTYARD_WATER_VISUAL_CONTRACT_RESULT' },
    @{ name = 'water-depth-continuity'; script = 'test_courtyard_water_depth_continuity.gd'; headless = $false; marker = 'COURTYARD_WATER_DEPTH_CONTINUITY_RESULT' },
    @{ name = 'adjacency'; script = 'test_courtyard_terrain_adjacency.gd'; headless = $false; marker = 'COURTYARD_ADJACENCY_RESULT' },
    @{ name = 'material-intake'; script = 'capture_courtyard_material_intake.gd'; headless = $false; marker = 'COURTYARD_MATERIAL_INTAKE_RESULT' },
    @{ name = 'whole-scene'; script = 'capture_courtyard_visual_review.gd'; headless = $false; marker = 'COURTYARD_VISUAL_CAPTURE_RESULT' },
    @{ name = 'interaction'; script = 'test_battlefield_courtyard.gd'; headless = $true; marker = 'BATTLEFIELD_COURTYARD_RESULT' }
)
$taskReceipt = [ordered]@{
    started_at_utc = [DateTime]::UtcNow.ToString('o')
    status = 'running'
    visual_acceptance = 'pending_user'
    baseline_status = 'candidate_unapproved'
    runner_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLower()
    steps = @()
}
$taskReceiptPath = Join-Path $taskOutput 'validation-run.json'
$taskSourceChecks = @{}

function Assert-Evidence([bool]$Condition, [string]$Reason) {
    if (-not $Condition) { throw $Reason }
}

function Assert-Fields($Record, [string[]]$Names) {
    Assert-Evidence ($null -ne $Record) '结果对象缺失。'
    foreach ($taskField in $Names) {
        Assert-Evidence ($Record.PSObject.Properties.Name -contains $taskField) ('结果缺少必要字段：' + $taskField)
    }
}

function Assert-BooleanTrue($Value, [string]$Name) {
    Assert-Evidence ($Value -is [bool] -and $Value) ($Name + ' 必须明确为 true。')
}

function Read-Evidence([string]$Name) {
    $taskFile = Join-Path $taskOutput $Name
    Assert-Evidence (Test-Path -LiteralPath $taskFile -PathType Leaf) ('缺少产物：' + $Name)
    return Get-Content -LiteralPath $taskFile -Raw | ConvertFrom-Json
}

function Assert-Image([string]$Name, [string]$Digest) {
    Assert-Evidence ($Name -eq [IO.Path]::GetFileName($Name)) '图像名称必须是输出目录内的文件名。'
    $taskFile = Join-Path $taskOutput $Name
    Assert-Evidence (Test-Path -LiteralPath $taskFile -PathType Leaf) ('缺少图像：' + $Name)
    Assert-Evidence ((Get-Item -LiteralPath $taskFile).Length -gt 0) ('图像为空：' + $Name)
    if ($Digest) {
        Assert-Evidence ((Get-FileHash -LiteralPath $taskFile -Algorithm SHA256).Hash -ieq $Digest) ('图像摘要不一致：' + $Name)
    }
}

function Assert-Sources($Digests) {
    Assert-Evidence ($null -ne $Digests) '来源摘要缺失。'
    foreach ($taskEntry in $Digests.PSObject.Properties) {
        $taskResource = $taskEntry.Name
        $taskDigest = [string]$taskEntry.Value
        Assert-Evidence ($taskResource.StartsWith('res://') -and $taskDigest -match '^[0-9a-fA-F]{64}$') '来源标识或摘要格式不符。'
        $taskSource = [IO.Path]::GetFullPath((Join-Path $taskProject $taskResource.Substring(6)))
        Assert-Evidence ($taskSource.StartsWith($taskProject.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) '来源路径超出项目。'
        Assert-Evidence (Test-Path -LiteralPath $taskSource -PathType Leaf) ('来源已缺失：' + $taskResource)
        Assert-Evidence ((Get-FileHash -LiteralPath $taskSource -Algorithm SHA256).Hash -ieq $taskDigest) ('来源已变化：' + $taskResource)
        if ($taskSourceChecks.ContainsKey($taskResource)) {
            Assert-Evidence ($taskSourceChecks[$taskResource] -ieq $taskDigest) ('不同步骤使用了不同来源：' + $taskResource)
        }
        $taskSourceChecks[$taskResource] = $taskDigest
    }
}

function Assert-StepEvidence([string]$Name, $Result) {
    switch ($Name) {
        'water-contract' {
            Assert-Fields $Result @('overall', 'negative_samples_blocked', 'positive_samples_passed', 'images_saved', 'source_hashes_stable')
            Assert-Evidence ($Result.overall -ceq 'PASS') '水岸检查未明确通过。'
            foreach ($taskField in @('negative_samples_blocked', 'positive_samples_passed', 'images_saved', 'source_hashes_stable')) {
                Assert-BooleanTrue $Result.$taskField $taskField
            }
            $taskReport = Read-Evidence 'water-visual-contract-report.json'
            Assert-Fields $taskReport @('overall', 'checker_results', 'image_sha256', 'source_sha256')
            Assert-Evidence ($taskReport.overall -ceq 'PASS') '水岸报告未通过。'
            Assert-Sources $taskReport.source_sha256
            foreach ($taskChecker in @('depth_semantics', 'depth_rendered_luminance', 'stone_bank_uniform_band')) {
                Assert-Fields $taskReport.checker_results @($taskChecker)
                Assert-BooleanTrue $taskReport.checker_results.$taskChecker.negative_blocked $taskChecker
            }
            foreach ($taskImage in @('water-depth-correct.png', 'water-depth-semantic-negative.png', 'water-depth-render-negative.png',
                'stone-bank-reference.png', 'stone-bank-current.png', 'stone-bank-legacy-negative.png', 'water-visual-diagnostic-comparison.png')) {
                Assert-Fields $taskReport.image_sha256 @($taskImage)
                Assert-Image $taskImage $taskReport.image_sha256.$taskImage
            }
        }
        'water-depth-continuity' {
            Assert-Fields $Result @('overall', 'negative_samples_blocked', 'positive_samples_passed', 'images_saved', 'source_hashes_stable')
            Assert-Evidence ($Result.overall -ceq 'PASS') '水深连续性检查未明确通过。'
            foreach ($taskField in @('negative_samples_blocked', 'positive_samples_passed', 'images_saved', 'source_hashes_stable')) {
                Assert-BooleanTrue $Result.$taskField $taskField
            }
            $taskReport = Read-Evidence 'water-depth-continuity-report.json'
            Assert-Fields $taskReport @('overall', 'positive_samples_passed', 'negative_samples_blocked', 'checker_results', 'image_sha256', 'source_sha256')
            Assert-Evidence ($taskReport.overall -ceq 'PASS') '水深连续性报告未通过。'
            Assert-BooleanTrue $taskReport.positive_samples_passed '水深连续性正例'
            Assert-BooleanTrue $taskReport.negative_samples_blocked '水深连续性错误对照'
            Assert-Fields $taskReport.checker_results @('curves', 'negative_curves', 'single_cell')
            foreach ($taskCurve in @('north_straight_into_basin', 'northwest_corner_into_basin', 'west_multicell_into_basin', 'off_map_extension_into_basin')) {
                Assert-Fields $taskReport.checker_results.curves @($taskCurve)
                Assert-BooleanTrue $taskReport.checker_results.curves.$taskCurve.passed $taskCurve
                Assert-Evidence ($taskReport.checker_results.curves.$taskCurve.values.Count -eq 17) '连续性曲线采样数不符。'
                if ($taskCurve -ne 'off_map_extension_into_basin') {
                    foreach ($taskFault in @('hard', 'legacy')) {
                        $taskNegative = $taskFault + '/' + $taskCurve
                        Assert-Fields $taskReport.checker_results.negative_curves @($taskNegative)
                        $taskRejected = $taskReport.checker_results.negative_curves.$taskNegative.passed
                        Assert-Evidence ($taskRejected -is [bool] -and -not $taskRejected) ('错误对照未被明确拒绝：' + $taskNegative)
                    }
                }
            }
            Assert-BooleanTrue $taskReport.checker_results.single_cell.passed '单格平缓低洼检查'
            Assert-Sources $taskReport.source_sha256
            foreach ($taskImage in @('water-depth-basin.png', 'water-depth-continuity-comparison.png')) {
                Assert-Fields $taskReport.image_sha256 @($taskImage)
                Assert-Image $taskImage $taskReport.image_sha256.$taskImage
            }
            foreach ($taskImage in $taskReport.image_sha256.PSObject.Properties) {
                Assert-Image $taskImage.Name $taskImage.Value
            }
        }
        'adjacency' {
            Assert-Fields $Result @('passed', 'failed')
            Assert-Evidence ($Result.failed -eq 0 -and $Result.passed -ge 14) '邻接检查缺失或失败。'
            Assert-Image 'terrain-adjacency.png' ''
        }
        'material-intake' {
            Assert-Fields $Result @('captures', 'identity_checks', 'visual_acceptance')
            Assert-Evidence ($Result.captures -eq 3 -and $Result.identity_checks -ceq 'pass' -and $Result.visual_acceptance -ceq 'pending_review') '素材检查结果不符合预期。'
            $taskReport = Read-Evidence 'material-intake.json'
            Assert-Fields $taskReport @('records', 'board_sha256', 'profile_sha256', 'script_sha256', 'source_manifest_sha256')
            Assert-Sources ([pscustomobject]@{
                'res://scripts/ui/playground/courtyard_board_view.gd' = $taskReport.board_sha256
                'res://assets/prototype/battlefield_courtyard/visual_profile.json' = $taskReport.profile_sha256
                'res://tests/capture_courtyard_material_intake.gd' = $taskReport.script_sha256
                'res://assets/prototype/battlefield_courtyard/source-manifest.json' = $taskReport.source_manifest_sha256
            })
            Assert-Evidence ($taskReport.records.Count -eq 3) '素材清单数量不符。'
            foreach ($taskMaterial in $taskReport.records) {
                Assert-Fields $taskMaterial @('file', 'image_sha256', 'identity_matches_manifest', 'source', 'source_sha256')
                Assert-BooleanTrue $taskMaterial.identity_matches_manifest '素材来源检查'
                Assert-Sources ([pscustomobject]@{ $taskMaterial.source = $taskMaterial.source_sha256 })
                Assert-Image $taskMaterial.file $taskMaterial.image_sha256
            }
        }
        'whole-scene' {
            Assert-Fields $Result @('captures', 'failed')
            Assert-Evidence ($Result.failed -eq 0 -and $Result.captures -eq 12) '整屏采集缺失或失败。'
            $taskReport = Read-Evidence 'capture-manifest.json'
            Assert-Fields $taskReport @('captures', 'baseline_status', 'sources_sha256')
            Assert-Sources $taskReport.sources_sha256
            Assert-Evidence ($taskReport.baseline_status -ceq 'candidate_unapproved' -and $taskReport.captures.Count -eq 12) '整屏清单数量或基线状态不符。'
            foreach ($taskLayout in @('overgrown', 'flooded', 'passage')) {
                foreach ($taskWidth in @(1280, 1920)) {
                    foreach ($taskView in @('play', 'clear')) {
                        $taskImage = "$taskLayout-$taskWidth-$taskView.png"
                        $taskEntry = @($taskReport.captures | Where-Object { $_.file -ceq $taskImage })
                        Assert-Evidence ($taskEntry.Count -eq 1) ('整屏状态缺失或重复：' + $taskImage)
                        Assert-Fields $taskEntry[0] @('sha256', 'repeated_frame_identical')
                        Assert-BooleanTrue $taskEntry[0].repeated_frame_identical '连续帧稳定性'
                        Assert-Image $taskImage $taskEntry[0].sha256
                    }
                }
            }
        }
        'interaction' {
            Assert-Fields $Result @('passed', 'failed')
            Assert-Evidence ($Result.failed -eq 0 -and $Result.passed -ge 97) '交互检查缺失或失败。'
        }
        default { throw ('未定义的检查步骤：' + $Name) }
    }
}

try {
    foreach ($taskStep in $taskSteps) {
        $taskArguments = @('--path', $taskProject, '--rendering-method', 'gl_compatibility', '--script', ('res://tests/' + $taskStep.script))
        if ($taskStep.headless) { $taskArguments += '--headless' }
        $taskArguments += @('--', ('--output=' + $taskOutput))
        $taskLogPath = Join-Path $taskOutput ($taskStep.name + '.log')
        $taskLog = @(& $GodotPath @taskArguments 2>&1 | Tee-Object -FilePath $taskLogPath)
        $taskExit = $LASTEXITCODE
        $taskResultLine = @($taskLog | Where-Object { $_.ToString().StartsWith($taskStep.marker + ' ') })
        $taskSuccess = $taskExit -eq 0 -and $taskResultLine.Count -eq 1
        if ($taskSuccess) {
            $taskResult = $taskResultLine[0].ToString().Substring($taskStep.marker.Length + 1) | ConvertFrom-Json
            try {
                Assert-StepEvidence $taskStep.name $taskResult
            } catch {
                $taskSuccess = $false
                Write-Output $_.Exception.Message
            }
        }
        $taskReceipt.steps += [ordered]@{ name = $taskStep.name; exit_code = $taskExit; valid_result_marker = ($taskResultLine.Count -eq 1); passed = $taskSuccess; log = ($taskStep.name + '.log') }
        $taskReceipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $taskReceiptPath -Encoding utf8
        if (-not $taskSuccess) { throw ('步骤未通过，后续采集停止：' + $taskStep.name) }
    }
    Assert-Sources ([pscustomobject]$taskSourceChecks)
    Assert-Evidence ((Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash -ieq $taskReceipt.runner_sha256) '入口脚本在运行中变化。'
    $taskReceipt.sources_sha256 = $taskSourceChecks
    $taskReceipt.status = 'automated_evidence_complete_review_pending'
    $taskReceipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $taskReceiptPath -Encoding utf8
    Write-Output '自动证据已完成。请继续逐项看图、独立审查和用户视觉验收；当前图像尚未成为批准基线。'
} catch {
    $taskReceipt.status = 'failed'
    $taskReceipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $taskReceiptPath -Encoding utf8
    throw
}
