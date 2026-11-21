# Installs/updates local-context globally (Windows). No git required.
#   irm https://raw.githubusercontent.com/Coosley/local-context/main/install.ps1 | iex
# Override: $env:CTX_REPO='owner/name'; $env:CTX_BRANCH='main'
$ErrorActionPreference = 'Stop'
$repo   = if ($env:CTX_REPO)   { $env:CTX_REPO }   else { 'Coosley/local-context' }
$branch = if ($env:CTX_BRANCH) { $env:CTX_BRANCH } else { 'main' }
$dest   = Join-Path $HOME '.local-context'
$tmp    = Join-Path ([IO.Path]::GetTempPath()) ('ctx-' + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp, $dest | Out-Null
try {
  $zip = Join-Path $tmp 'ctx.zip'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/$branch.zip" -OutFile $zip -UseBasicParsing
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
Write-Host "Installed local-context to $dest"
Write-Host "Next: cd into any workspace and run:  ctx init"
