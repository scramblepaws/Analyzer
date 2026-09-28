# Analyzer contract gate. Run before every push: powershell -ExecutionPolicy Bypass -File check.ps1
# Fails (exit 1) on any violation. What it enforces and why (executor lessons):
#   1. Parse-clean under luaparser (catches unbalanced blocks locally).
#   2. No Drawing.new("Circle") — square UI only, circles don't pool-detect cleanly.
#   3. No non-ASCII glyphs in widget text (Drawing font renders them as ?).
#   4. No GetMouseLocation — InputObject.Position only (inset math misaligned clicks).
#   5. No '...' inside a nested non-vararg closure — Luau rejects, Lua parsers allow.
#   6. Bundle rebuilds and re-parses (release artifact never drifts from source).
$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
$failed = $false

function Fail($msg) {
    Write-Output ("CHECK-FAIL: " + $msg)
    $script:failed = $true
}

$src = @("loader.lua", "ui_framework.lua", "explorer.lua", "properties.lua", "script_viewer.lua", "remote_spy.lua", "export.lua")

# 1. parse
foreach ($f in $src) {
    $r = & luaparser $f 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Fail("$f does not parse") }
}

# 2-4. ban lists (source files only, bundle is generated).
# Comments (line + long-bracket spans) and loader console-output lines can't reach
# Drawing, so they're skipped; any other non-ASCII would render as ? in-game.
$bans = @{
    'Drawing\.new\("Circle"\)' = "Circle drawing (square UI only)";
    'GetMouseLocation' = "GetMouseLocation (use InputObject.Position)";
}
foreach ($f in $src) {
    $lines = Get-Content -LiteralPath $f
    $inBlock = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $raw = $lines[$i]
        if (-not $inBlock -and $raw -match "--\[\[") {
            if ($raw -notmatch "\]\]") { $inBlock = $true }
            continue
        }
        if ($inBlock) {
            if ($raw -match "\]\]") { $inBlock = $false }
            continue
        }
        $code = $raw -replace "--.*$", ""
        if ($f -eq "loader.lua" -and $code -match "print\(|warn\(|table\.insert\(lines|local icon =|^\s*`"") { continue }
        foreach ($pat in $bans.Keys) {
            if ($code -match $pat) { Fail("$f line " + ($i + 1) + ": " + $bans[$pat]) }
        }
        if ($code -match "[^\x00-\x7F]") {
            Fail("$f line " + ($i + 1) + ": non-ASCII in game-facing code (Drawing font shows ?)")
        }
    }
}

# 5. nested-vararg check: every code '...' must belong to a vararg function.
# Stack of multi-line headers (indent-aware); single-line closures checked inline.
foreach ($f in $src) {
    $lines = Get-Content -LiteralPath $f
    $stack = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $code = ($line -replace "--.*$", "") -replace '"[^"]*"', '""'
        $headers = [regex]::Matches($code, "function[^(]*\(([^)]*)\)")
        $selfContained = $code -match "\bend\b"
        if ($headers.Count -gt 0 -and -not $selfContained) {
            foreach ($hh in $headers) {
                $h = $hh.Value
                $ind = $line.IndexOf($h)
                $sp = 0; while ($sp -lt $ind -and $line[$sp] -eq ' ') { $sp++ }
                $stack += @(@{ind = $sp; va = ($hh.Groups[1].Value -match "\.\.\.")})
            }
        }
        $bare = $code
        foreach ($hh in $headers) { $bare = $bare.Replace($hh.Value, "fn()") }
        if ($bare -match "\.\.\.") {
            if ($headers.Count -gt 0 -and $selfContained) {
                $last = $headers[$headers.Count - 1].Groups[1].Value
                if ($last -notmatch "\.\.\.") { Fail("$f line " + ($i + 1) + ": '...' in non-vararg closure") }
            }
            elseif ($stack.Count -eq 0 -or -not $stack[-1].va) {
                Fail("$f line " + ($i + 1) + ": '...' with no vararg function above it")
            }
        }
        if ($line -match "^(\s*)end\b") {
            $ind = $Matches[1].Length
            while ($stack.Count -gt 0 -and $stack[-1].ind -ge $ind) {
                if ($stack.Count -eq 1) { $stack = @() } else { $stack = $stack[0..($stack.Count - 2)] }
            }
        }
    }
}

if ($failed) { Write-Output "GATE FAILED"; exit 1 }

# 6. rebuild + re-verify bundle
powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\build_bundle.ps1"
$r = & luaparser "$PSScriptRoot\analyzer.bundle.lua" 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Fail("bundle does not parse") exit 1 }

Write-Output "GATE PASSED"
