param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$PythonPath = 'python',
    [switch]$SkipTerrain,
    [string[]]$BatchNames = @()
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (-not [IO.Path]::IsPathRooted($OutputDirectory) -or (Test-Path -LiteralPath $output)) {
    throw '请提供新的仓库外绝对输出目录。'
}
if ($output -eq $project -or $output.StartsWith($project.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '证据必须位于仓库外。'
}
. (Join-Path $PSScriptRoot 'claude_review/capture-gate.ps1')
Assert-CaptureProject $project
New-Item -ItemType Directory -Path $output | Out-Null
$receipt = [ordered]@{result='running'; terrain_included=(-not $SkipTerrain); requested_batches=$BatchNames; batches=@()}
try {
    if (-not $SkipTerrain) {
        & (Join-Path $PSScriptRoot 'run_terrain_runtime_validation.ps1') -GodotPath $GodotPath -PythonPath $PythonPath -OutputDirectory (Join-Path $output 'terrain')
    }
    $batches = @(
        @{name='hud-final'; script='tests/capture_hud_final_acceptance.gd'},
        @{name='hud-character'; script='tests/capture_hud_character_panel.gd'},
        @{name='hud-crest'; script='tests/capture_hud_crest_candidate.gd'},
        @{name='hud-number'; script='tests/capture_hud_number_candidate.gd'},
        @{name='hud-freeze'; script='tests/capture_hud_freeze.gd'},
        @{name='action-resources'; script='tests/capture_action_resource_bar_tactical.gd'; extra=@('--capture-action-resources')},
        @{name='kensei-token'; script='tests/capture_kensei_map_token_tactical.gd'; extra=@('--capture-all')},
        @{name='environment-motion'; script='tests/capture_battlefield_environment_motion.gd'; engine=@('--fixed-fps', '24')},
        @{name='battle-overlays'; script='tests/claude_review/capture_battle_overlays.gd'},
        @{name='run-flow'; script='tests/claude_review/capture_run_flow_ui.gd'},
        @{name='portrait'; script='dev_doc/ui-art-research/hud-myrmidon-portrait/capture_review.gd'},
        @{name='skill-icons'; script='dev_doc/ui-art-research/myrmidon-skill-icons/capture_candidate.gd'},
        @{name='native-battle'; script='tests/claude_review/capture_scene_native.gd'; extra=@('--scene=res://scenes/tactical/TacticalScene.tscn')},
        @{name='native-courtyard'; script='tests/claude_review/capture_scene_native.gd'; extra=@('--scene=res://scenes/playground/battlefield_courtyard.tscn')},
        @{name='native-painter'; script='tests/claude_review/capture_scene_native.gd'; extra=@('--scene=res://scenes/playground/terrain_painter.tscn')}
    )
    if ($BatchNames.Count -gt 0) {
        foreach ($name in $BatchNames) {
            if ($name -notin $batches.name) { throw ('未知视觉批次：' + $name) }
        }
        $batches = @($batches | Where-Object { $_.name -in $BatchNames })
    }
    foreach ($batch in $batches) {
        $directory = Join-Path $output $batch.name
        New-Item -ItemType Directory -Path $directory | Out-Null
        $engineArguments = if ($batch.ContainsKey('engine')) { @($batch.engine) } else { @() }
        $arguments = @('--path', $project, '--script', ('res://' + $batch.script)) + $engineArguments + @('--', ('--output=' + $directory)) + @($batch.extra)
        $lines = @(& $GodotPath @arguments 2>&1)
        $exitCode = $LASTEXITCODE
        $lines | Set-Content -LiteralPath (Join-Path $directory 'run.log') -Encoding utf8
        if ($exitCode -ne 0 -or ($lines -join "`n") -match '(?m)^(SCRIPT ERROR|ERROR:)|ObjectDB instances leaked|resources still in use') {
            throw ('视觉批次运行失败：' + $batch.name)
        }
        Invoke-CaptureC8 -ProjectRoot $project -PythonPath $PythonPath -Directory $directory -Name $batch.name
        $receipt.batches += @{name=$batch.name; result='pass'; source=$batch.script; source_sha256=(Get-FileHash -LiteralPath (Join-Path $project $batch.script) -Algorithm SHA256).Hash.ToLowerInvariant()}
        $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'visual-resolution-validation.json') -Encoding utf8
    }
    $receipt.result = 'pass'
} catch {
    $receipt.result = 'fail'
    $receipt.failure = $_.Exception.Message
    throw
} finally {
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'visual-resolution-validation.json') -Encoding utf8
}
