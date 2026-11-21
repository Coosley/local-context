<#
.SYNOPSIS  Local-context scaffolder. Harness-agnostic: creates a git-ignored .context/ brain in a workspace.
.EXAMPLE   .\ctx.ps1 init C:\code\myapp
.EXAMPLE   .\ctx.ps1 init . -Pointer AGENTS.md,CLAUDE.md
.EXAMPLE   .\ctx.ps1 status .
.EXAMPLE   .\ctx.ps1 upgrade .       # refresh START_HERE.md protocol only
#>
param(
  [Parameter(Position = 0)][string]$Command = 'help',
  [Parameter(Position = 1)][string]$Path = '.',
  [string[]]$Pointer = @()   # optional: names of instruction files your harness reads (any name you choose)
)
$ErrorActionPreference = 'Stop'
$src = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'templates'
$bootstrap = 'Read .context/START_HERE.md and follow it. It is this workspace''s local project memory.'

function Get-ExcludeFile($ws) {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $g = git -C $ws rev-parse --git-path info/exclude 2>$null
  $ok = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $old
  if (-not $ok -or -not $g) { return $null }
  if (-not [IO.Path]::IsPathRooted($g)) { $g = Join-Path $ws $g }
  return $g
}

function Add-Exclude($ws, $entry) {
  $f = Get-ExcludeFile $ws
  if (-not $f) { return $false }
  New-Item -ItemType Directory -Force -Path (Split-Path $f) | Out-Null
  $has = (Test-Path $f) -and ((Get-Content $f) -contains $entry)
  if (-not $has) { Add-Content -Path $f -Value $entry }
  return $true
}

function Test-Tracked($ws, $file) {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = git -C $ws ls-files --error-unmatch -- $file 2>$null
  $r = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $old
  return $r
}

switch ($Command) {
  'init' {
    $ws = (Resolve-Path $Path).Path
    $ctx = Join-Path $ws '.context'
    New-Item -ItemType Directory -Force -Path $ctx | Out-Null
    $created = 0
    Get-ChildItem $src -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($src.Length).TrimStart('\', '/')
      $dest = Join-Path $ctx $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
      if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest; $created++ }
    }
    Copy-Item (Join-Path $src 'START_HERE.md') (Join-Path $ctx 'START_HERE.md') -Force
    $ex = Add-Exclude $ws '.context/'
    foreach ($p in $Pointer) {
      $pf = Join-Path $ws $p
      $block = "<!-- local-context:start -->`n$bootstrap`n<!-- local-context:end -->`n"
      if ((Test-Path $pf) -and ((Get-Content $pf -Raw) -match 'local-context:start')) { continue }
      if (Test-Path $pf) { Add-Content $pf "`n$block" } else { Set-Content $pf $block -Encoding utf8 }
      if (-not (Test-Tracked $ws $p)) { [void](Add-Exclude $ws $p) }
      else { Write-Warning "$p is tracked by git; the pointer block was added but will show up as a change." }
    }
    Write-Host "Context ready: $ctx ($created new files)"
    if ($ex) { Write-Host "Excluded via .git/info/exclude (local only, nothing committed)." }
    else { Write-Host "Not a git repo (or git missing): nothing to exclude yet. Re-run init after 'git init'." }
    Write-Host "`nPaste this into ANY agent/harness (or put it in its instruction file):`n  $bootstrap"
  }
  'upgrade' {
    $ctx = Join-Path (Resolve-Path $Path).Path '.context'
    Copy-Item (Join-Path $src 'START_HERE.md') (Join-Path $ctx 'START_HERE.md') -Force
    Write-Host 'START_HERE.md refreshed.'
  }
  'status' {
    $ctx = Join-Path (Resolve-Path $Path).Path '.context'
    if (-not (Test-Path $ctx)) { Write-Host 'No .context here. Run: ctx.ps1 init'; break }
    Get-Content (Join-Path $ctx 'STATE.md')
    Write-Host "`n--- Open checklist items ---"
    $files = @(Get-ChildItem $ctx -Recurse -Include *.md -File | Where-Object { $_.Name -ne '_template.md' -and $_.Name -ne 'START_HERE.md' })
    foreach ($f in $files) {
      $open = @(Select-String -Path $f.FullName -Pattern '^\s*- \[( |~|!)\]' | Where-Object { $_.Line -notmatch '<' })
      if ($open.Count) {
        Write-Host ("{0}: {1} open" -f $f.FullName.Substring($ctx.Length + 1), $open.Count)
        $open | ForEach-Object { Write-Host ("  " + $_.Line.Trim()) }
      }
    }
  }
  'update' {
    $rf = Join-Path (Split-Path -Parent $src) 'repo.txt'
    if (-not (Test-Path $rf)) { Write-Host 'No repo.txt: installed from a clone? Use git pull there.'; break }
    $r = Get-Content $rf
    Invoke-RestMethod "https://raw.githubusercontent.com/$($r[0])/$($r[1])/install.ps1" | Invoke-Expression
  }
  default {
    Write-Host "Usage: ctx <init|status|upgrade|update> [path] [-Pointer file1,file2]"
  }
}
