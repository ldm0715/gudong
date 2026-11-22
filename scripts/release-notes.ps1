# Extracts the release body for a version from changeslog.md and injects the
# SHA-256 table produced by the packaging step.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\release-notes.ps1 `
#     -Version 0.1.0 -ChecksumsFile dist\checksums.md -Output dist\release-notes.md

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Changelog = "changeslog.md",

    [string]$ChecksumsFile,

    [string]$Output = "dist/release-notes.md"
)

$ErrorActionPreference = "Stop"
$Version = $Version.TrimStart("v")

function Get-ChangelogSection {
    param([string]$Path, [string]$Version)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $escaped = [regex]::Escape($Version)
    $pattern = "(?ms)^##\s+$escaped\s+[—-][^\r\n]*(?:\r?\n)+.*?(?=^##\s|\z)"
    $match = [regex]::Match($text, $pattern)
    if ($match.Success) {
        return $match.Value.Trim()
    }
    return $null
}

function Get-CommitNotes {
    param([string]$Version)

    $previousTag = $null
    try {
        $previousTag = git describe --tags --abbrev=0 2>$null
    } catch {
        $previousTag = $null
    }
    if ($LASTEXITCODE -ne 0) {
        $previousTag = $null
    }

    if ($previousTag) {
        $range = "$previousTag..HEAD"
    } else {
        $range = "HEAD"
    }

    $subjects = @(git log $range --pretty=format:"%s")
    $groups = [ordered]@{
        "新增" = New-Object System.Collections.Generic.List[string]
        "修复" = New-Object System.Collections.Generic.List[string]
        "变更" = New-Object System.Collections.Generic.List[string]
    }

    foreach ($subject in $subjects) {
        if ($subject -match "^(?<type>[a-z]+)(\([^)]*\))?!?:\s*(?<message>.+)$") {
            $type = $Matches["type"]
            $message = $Matches["message"]
            switch ($type) {
                "feat" { $groups["新增"].Add($message) }
                "fix" { $groups["修复"].Add($message) }
                "perf" { $groups["变更"].Add($message) }
                "refactor" { $groups["变更"].Add($message) }
                "revert" { $groups["修复"].Add($message) }
            }
        }
    }

    $date = (Get-Date).ToString("yyyy-MM-dd")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("## $Version — $date")
    $lines.Add("")
    $lines.Add("本版说明未在 changeslog.md 中找到，以下内容由提交记录自动生成。")

    foreach ($name in $groups.Keys) {
        $items = @($groups[$name] | Select-Object -Unique)
        if ($items.Count -eq 0) {
            continue
        }
        $lines.Add("")
        $lines.Add("### $name")
        $lines.Add("")
        foreach ($item in $items) {
            $lines.Add("- $item")
        }
    }

    return ($lines -join "`n")
}

$notes = Get-ChangelogSection -Path $Changelog -Version $Version
if ($notes) {
    Write-Host "Using changeslog.md section for $Version."
} else {
    Write-Host "No changeslog.md section for $Version; generating notes from git log."
    $notes = Get-CommitNotes -Version $Version
}

if ($ChecksumsFile -and (Test-Path -LiteralPath $ChecksumsFile)) {
    $checksums = (Get-Content -LiteralPath $ChecksumsFile -Raw -Encoding UTF8).Trim()
    if ($notes.Contains("<!--CHECKSUMS-->")) {
        $notes = $notes.Replace("<!--CHECKSUMS-->", $checksums)
    } else {
        $notes = "$notes`n`n### 校验`n`n$checksums"
    }
}

$fullPath = [System.IO.Path]::GetFullPath($Output)
$directory = [System.IO.Path]::GetDirectoryName($fullPath)
if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($fullPath, $notes.TrimEnd() + "`n", $utf8)
Write-Host "Release notes written to $fullPath."
