param(
    [Parameter(Mandatory = $true)]
    [string] $ArchivePath
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$manifestPath = Join-Path $repoRoot 'dev_doc/ui-art-research/myrmidon-skill-icons/source-manifest.json'
$catalogPath = Join-Path $repoRoot 'assets/ui/catalogs/hud_m2_skill_icons.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json

function Assert-Export([bool] $condition, [string] $message) {
    if (-not $condition) { throw $message }
}

function Get-EntryBytes([System.IO.Compression.ZipArchiveEntry] $entry) {
    $stream = $entry.Open()
    try {
        $buffer = [System.IO.MemoryStream]::new()
        try {
            $stream.CopyTo($buffer)
            return $buffer.ToArray()
        } finally {
            $buffer.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

Assert-Export ($manifest.status -eq 'user_approved') '图标来源清单尚未标记为用户定版。'
Assert-Export ($manifest.assets.Count -eq 5) '来源清单中的运行图数量不是五张。'
Assert-Export (Test-Path -LiteralPath $ArchivePath -PathType Leaf) '找不到待检查的资源包。'
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ArchivePath).Path)
try {
    $entries = @{}
    foreach ($entry in $archive.Entries) { $entries[$entry.FullName] = $entry }
    $catalogEntry = 'assets/ui/catalogs/hud_m2_skill_icons.json'
    Assert-Export $entries.ContainsKey($catalogEntry) '资源包缺少技能图标目录 JSON。'
    $packCatalogBytes = Get-EntryBytes $entries[$catalogEntry]
    $localCatalogHash = (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $packCatalogHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($packCatalogBytes)).ToLowerInvariant()
    Assert-Export ($localCatalogHash -eq $packCatalogHash) '资源包内的技能图标目录与仓库文件不一致。'

    $checked = @()
    foreach ($asset in $manifest.assets) {
        $runtimePath = $asset.runtime.Replace('\', '/')
        $runtimeFile = Join-Path $repoRoot $asset.runtime
        $sourceFile = Join-Path (Split-Path $manifestPath -Parent) $asset.source
        Assert-Export ((Get-FileHash -LiteralPath $runtimeFile -Algorithm SHA256).Hash.ToLowerInvariant() -eq $asset.runtime_sha256) "运行图摘要不符：$($asset.skill_id)"
        Assert-Export ((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash.ToLowerInvariant() -eq $asset.source_sha256) "开发源图摘要不符：$($asset.skill_id)"
        Assert-Export ($catalog._class_overrides.myrmidon.($asset.skill_id) -eq "res://$runtimePath") "目录映射不符：$($asset.skill_id)"

        $importPath = "$runtimePath.import"
        Assert-Export $entries.ContainsKey($importPath) "资源包缺少运行图导入映射：$($asset.skill_id)"
        $importText = [Text.Encoding]::UTF8.GetString((Get-EntryBytes $entries[$importPath]))
        $match = [regex]::Match($importText, '(?m)^path="res://([^"]+\.ctex)"\r?$')
        Assert-Export $match.Success "无法读取导入纹理路径：$($asset.skill_id)"
        $texturePath = $match.Groups[1].Value
        Assert-Export ($entries.ContainsKey($texturePath) -and $entries[$texturePath].Length -gt 0) "资源包缺少运行纹理：$($asset.skill_id)"
        $checked += [ordered]@{ skill_id = $asset.skill_id; import = $importPath; texture = $texturePath }
    }

    foreach ($entryName in $entries.Keys) {
        Assert-Export (-not ($entryName -match '^(dev_doc|docs|tests)/')) "资源包包含开发或评审文件：$entryName"
    }
    foreach ($view in $manifest.verification_views) {
        $viewPath = "dev_doc/ui-art-research/myrmidon-skill-icons/$($view.path)"
        Assert-Export (-not $entries.ContainsKey($viewPath)) "资源包包含评审截图：$viewPath"
    }

    [ordered]@{
        result = 'pass'
        archive_sha256 = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        archive_bytes = (Get-Item -LiteralPath $ArchivePath).Length
        archive_entries = $archive.Entries.Count
        catalog_sha256 = $packCatalogHash
        runtime_assets = $checked
        excluded_roots = @('dev_doc/', 'docs/', 'tests/')
    } | ConvertTo-Json -Depth 5
} finally {
    $archive.Dispose()
}
