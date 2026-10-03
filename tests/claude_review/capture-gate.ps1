# 采集入口共用的配置及 C8 检查；不改写采集清单中的实际参数。
function Assert-CaptureProject([string]$ProjectRoot) {
    $text = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'project.godot'))
    $section = [regex]::Match($text, '(?ms)^\[rendering\]\r?\n(.*?)(?=^\[|\z)')
    if (-not $section.Success -or
        $section.Groups[1].Value -notmatch '(?m)^renderer/rendering_method="gl_compatibility"\r?$') {
        throw 'D-5 要求项目显式使用 gl_compatibility；停止采集。'
    }
}

function Invoke-CaptureC8 {
    param(
        [string]$ProjectRoot,
        [string]$PythonPath,
        [string]$Directory,
        [string]$Name
    )
    $source = Join-Path $Directory 'capture-metadata.json'
    $snapshot = Join-Path $Directory ($Name + '-capture-metadata.json')
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw ('缺少采集清单：' + $Name) }
    if (Test-Path -LiteralPath $snapshot) { throw ('采集身份快照已存在：' + $Name) }
    Copy-Item -LiteralPath $source -Destination $snapshot
    $resultPath = Join-Path $Directory ($Name + '-c8.json')
    & $PythonPath (Join-Path $ProjectRoot 'tests/claude_review/claude_review_checks.py') --c8-only --manifests $snapshot --json $resultPath
    if ($LASTEXITCODE -ne 0) { throw ('C8 采集身份检查失败：' + $Name) }
    $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($result.pass -isnot [bool] -or -not $result.pass) { throw ('C8 未明确通过：' + $Name) }
    $coveragePath = Join-Path $Directory ($Name + '-resolutions.json')
    & $PythonPath (Join-Path $ProjectRoot 'tests/claude_review/resolution_coverage.py') --manifests $snapshot --json $coveragePath
    if ($LASTEXITCODE -ne 0) { throw ('CR-23 三档画面状态覆盖检查失败：' + $Name) }
}
