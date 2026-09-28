# Builds analyzer.bundle.lua: loader + all modules embedded (single HttpGet, zero
# cross-file cache skew). Re-run after ANY module change, then commit + push.
# Usage: powershell -ExecutionPolicy Bypass -File build_bundle.ps1
$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

$files = @("ui_framework.lua", "export.lua", "explorer.lua", "properties.lua", "script_viewer.lua", "remote_spy.lua")
$loader = [System.IO.File]::ReadAllText("$PSScriptRoot\loader.lua")
$anchor = "local EMBEDDED = nil --[[BUNDLE_ANCHOR]]"
if (-not $loader.Contains($anchor)) { throw "anchor missing in loader.lua" }

$parts = @("local EMBEDDED = {")
foreach ($f in $files) {
    $src = [System.IO.File]::ReadAllText("$PSScriptRoot\$f") -replace "`r`n", "`n"
    if ($src.Contains("]===]")) { throw "delimiter collision in $f" }
    $stripped = ($src -split "`n" | Where-Object { $_ -notmatch "^return (UI|Explorer|Properties|SV|Spy|Export)$" }) -join "`n"
    $parts += '["' + $f + '"] = [===[' + "`n" + $stripped + "`n]===],"
}
$parts += "}"
$bundle = $loader.Replace($anchor, ($parts -join "`n"))
$enc = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$PSScriptRoot\analyzer.bundle.lua", $bundle, $enc)
Write-Output ("wrote analyzer.bundle.lua (" + $bundle.Length + " chars)")
