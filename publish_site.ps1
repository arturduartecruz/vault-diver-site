# publish_site.ps1 — one-command publish of the Vault Diver website to GitHub Pages.
#
# What it does:
#   1. Copies your exported HTML over index.html in this repo.
#   2. If nothing actually changed, stops (no empty commit).
#   3. Commits + pushes to GitHub (main branch).
#   4. Waits until the LIVE site actually serves the new bytes, then confirms.
#
# Usage:
#   pwsh -File publish_site.ps1
#       -> publishes C:\Users\artur\Downloads\Vault Diver Website.html
#   pwsh -File publish_site.ps1 -Source "C:\path\to\some other.html"
#       -> publishes a different file
#
# The exported file only needs to be a single self-contained .html
# (all images/CSS/JS inlined), which is what Claude's artifact export gives you.

param(
    [string]$Source = "C:\Users\artur\Downloads\Vault Diver Website.html"
)

$ErrorActionPreference = "Stop"
$repo = $PSScriptRoot
$dest = Join-Path $repo "index.html"
$url  = "https://arturduartecruz.github.io/vault-diver-site/"

function Fail($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }

if (-not (Test-Path $Source)) { Fail "Source file not found: $Source" }

# 1. Copy the export into place.
Copy-Item $Source $dest -Force
Write-Host "Copied '$Source' -> index.html" -ForegroundColor Cyan

# 2. Stage; bail out if there's no actual change.
git -C $repo add index.html
git -C $repo diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "No change — the live site already matches this file. Nothing to publish." -ForegroundColor Yellow
    exit 0
}

# 3. Commit + push.
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
git -C $repo commit -q -m "Update website ($stamp)"
Write-Host "Committed. Pushing..." -ForegroundColor Cyan
git -C $repo push -q origin main
if ($LASTEXITCODE -ne 0) { Fail "Push failed — check your internet / GitHub login (run: gh auth status)." }
Write-Host "Pushed to GitHub." -ForegroundColor Green

# 4. Wait for GitHub Pages to redeploy, then verify the live bytes match.
$want = (Get-FileHash $dest -Algorithm MD5).Hash
$tmp  = Join-Path $env:TEMP "vd_site_live.html"
Write-Host "Waiting for the live site to update (usually under a minute)..." -ForegroundColor Cyan
$updated = $false
for ($i = 1; $i -le 20; $i++) {
    Start-Sleep -Seconds 12
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -Headers @{ "Cache-Control" = "no-cache" } -ErrorAction Stop
        $live = (Get-FileHash $tmp -Algorithm MD5).Hash
        if ($live -eq $want) { $updated = $true; break }
    } catch { }
    Write-Host "  ...still deploying (check $i)" -ForegroundColor DarkGray
}
Remove-Item $tmp -ErrorAction SilentlyContinue

if ($updated) {
    Write-Host "`nLIVE ✓  $url" -ForegroundColor Green
    Write-Host "(If your browser still shows the old page, hard-refresh: Ctrl+Shift+R)" -ForegroundColor DarkGray
} else {
    Write-Host "`nPushed OK, but the live site hasn't reflected it after ~4 min." -ForegroundColor Yellow
    Write-Host "GitHub Pages is sometimes slow — check $url again shortly." -ForegroundColor Yellow
}
