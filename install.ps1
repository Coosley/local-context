# Installs/updates ctx globally (Windows). No git required.
#   irm https://raw.githubusercontent.com/Coosley/local-context/main/install.ps1 | iex
# Installs the latest tagged release if one exists, otherwise the main branch.
# Pin anything: $env:CTX_REF = 'v0.1.0'  (a tag, branch or full commit SHA)
# Other overrides: $env:CTX_REPO='owner/name'; $env:CTX_BRANCH='main'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo   = if ($env:CTX_REPO)   { $env:CTX_REPO }   else { 'Coosley/local-context' }
$branch = if ($env:CTX_BRANCH) { $env:CTX_BRANCH } else { 'main' }
$ref    = $env:CTX_REF
if (-not $ref) {
  try { $ref = (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing).tag_name } catch { $ref = $null }
}
if (-not $ref) { $ref = $branch }
$dest = Join-Path $HOME '.local-context'
$old  = if (Test-Path (Join-Path $dest 'VERSION')) { (Get-Content (Join-Path $dest 'VERSION') -TotalCount 1).Trim() } else { $null }
$url  = "https://github.com/$repo/archive/$ref.zip"
Write-Host "Source: $url"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ctx-' + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp, $dest | Out-Null
try {
  $zip = Join-Path $tmp 'ctx.zip'
  Invoke-WebRequest $url -OutFile $zip -UseBasicParsing
  Expand-Archive $zip -DestinationPath $tmp -Force
  $root = Get-ChildItem $tmp -Directory | Select-Object -First 1
  Copy-Item (Join-Path $root.FullName '*') $dest -Recurse -Force
  Set-Content (Join-Path $dest 'repo.txt') "$repo`n$branch"
} finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$user = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($user -split ';') -notcontains $dest) {
  [Environment]::SetEnvironmentVariable('Path', ($user.TrimEnd(';') + ';' + $dest), 'User')
  $env:Path += ";$dest"
  Write-Host "Added $dest to your user PATH (open a new terminal to pick it up)."
}
$new = if (Test-Path (Join-Path $dest 'VERSION')) { (Get-Content (Join-Path $dest 'VERSION') -TotalCount 1).Trim() } else { 'dev' }
if ($old -and $old -ne $new) { Write-Host "Updated ctx $old -> $new ($ref) in $dest" } else { Write-Host "Installed ctx $new ($ref) in $dest" }
Write-Host "Next: cd into any workspace and run:  ctx init"
