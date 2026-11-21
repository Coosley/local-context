<#
.SYNOPSIS  ctx - harness-agnostic local context (a git-ignored .context/ brain per workspace).
.DESCRIPTION
  ctx init [path] [-Pointer f1,f2]   create .context/, hide from git, scan repo, first snapshot
  ctx status|brief|doctor|wrap|archive|scan|bootstrap|snapshot|history|backup|team [path]
  ctx restore <file> [rev]           restore a file from snapshot history (workspace = cwd)
  ctx upgrade [path]                 refresh START_HERE.md in a workspace
  ctx update [ref]                   update the tool (latest release, or a tag/branch/sha)
  ctx uninstall -Yes                 remove the tool (workspaces untouched)
  ctx version
#>
param(
  [Parameter(Position = 0)][string]$Command = 'help',
  [Parameter(Position = 1)][string]$Path = '.',
  [Parameter(Position = 2)][string]$Extra = '',
  [string[]]$Pointer = @(),
  [switch]$Yes
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch {}
$self = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $self 'templates'
$Utf8 = New-Object Text.UTF8Encoding($false)
$bootstrap = 'Read .context/START_HERE.md and follow it. It is this workspace''s local project memory.'
$ItemPat = '^\s*-\s+(\S+)\s*\|\s*(NOT STARTED|IN PROGRESS|IN REVIEW|BLOCKED|FAILED|ABANDONED|COMPLETED)\s+(\d+)%'
$Always = 'STATE.md', 'donts.md', 'preferences.md', 'security.md'
$SecretPats = @(
  'AKIA[0-9A-Z]{16}', 'gh[pousr]_[A-Za-z0-9]{30,}', 'sk-[A-Za-z0-9]{20,}', 'xox[baprs]-[A-Za-z0-9-]{10,}',
  '-----BEGIN [A-Z ]*PRIVATE KEY-----', 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.',
  '(?i)(password|passwd|secret|api[_-]?key|token)\s*[:=]\s*[''"]?[A-Za-z0-9/+_\-]{12,}'
)

# ---------- helpers ----------
function Test-HasGit { [bool](Get-Command git -ErrorAction SilentlyContinue) }

function Invoke-Git {
  param([string]$Dir, [string[]]$GitArgs)
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = & git -C $Dir @GitArgs 2>$null; $script:GitOk = ($LASTEXITCODE -eq 0); $out }
  finally { $ErrorActionPreference = $old }
}

function Get-Ctx([string]$p) {
  $ws = (Resolve-Path $p).Path; $c = Join-Path $ws '.context'
  if (-not (Test-Path $c)) { Write-Host "No .context in $ws. Run: ctx init"; exit 1 }
  $c
}

function Get-ExcludeFile($ws) {
  if (-not (Test-HasGit)) { return $null }
  $g = Invoke-Git $ws @('rev-parse', '--git-path', 'info/exclude')
  if (-not $script:GitOk -or -not $g) { return $null }
  if (-not [IO.Path]::IsPathRooted($g)) { $g = Join-Path $ws $g }
  $g
}

function Add-Exclude($ws, $entry) {
  $f = Get-ExcludeFile $ws
  if (-not $f) { return $false }
  New-Item -ItemType Directory -Force -Path (Split-Path $f) | Out-Null
  $has = (Test-Path $f) -and ((Get-Content $f) -contains $entry)
  if (-not $has) { Add-Content -Path $f -Value $entry }
  $true
}

function Test-Tracked($ws, $file) {
  if (-not (Test-HasGit)) { return $false }
  [void](Invoke-Git $ws @('ls-files', '--error-unmatch', '--', $file))
  $script:GitOk
}

function Save-Snapshot($ctx, [string]$msg) {
  if (-not (Test-HasGit)) { return $false }
  if (-not (Test-Path (Join-Path $ctx '.git'))) { [void](Invoke-Git $ctx @('init', '-q')) }
  $gi = Join-Path $ctx '.gitignore'
  if (-not (Test-Path $gi)) { [IO.File]::WriteAllText($gi, ".locks/`n", $Utf8) }
  [void](Invoke-Git $ctx @('add', '-A'))
  $st = Invoke-Git $ctx @('status', '--porcelain')
  if (-not $st) { return $false }
  [void](Invoke-Git $ctx @('-c', 'user.name=ctx', '-c', 'user.email=ctx@localhost', '-c', 'commit.gpgsign=false', 'commit', '-q', '--no-verify', '-m', $msg))
  $script:GitOk
}

function Get-CtxFiles($ctx) {
  Get-ChildItem $ctx -Recurse -Include *.md -File | Where-Object {
    $_.FullName -notmatch '\\(archive|\.git)\\' -and $_.Name -notin '_template.md', 'START_HERE.md', 'scan.md'
  }
}

function Get-Rel($f) { $f.FullName -replace '^.*\\\.context\\', '' }

function Get-Items($f) {
  @(Select-String -Path $f.FullName -Pattern $ItemPat -Encoding UTF8 | Where-Object {
      $p = $_.Line -split '\|'; ([string]$p[2]).Trim() -notmatch '^<[^>]*>$' })
}

function Show-Progress($ctx) {
  foreach ($f in Get-CtxFiles $ctx) {
    $items = Get-Items $f
    if (-not $items.Count) { continue }
    $c = @{}
    foreach ($m in $items) { $s = $m.Matches[0].Groups[2].Value; $c[$s] = 1 + [int]$c[$s] }
    $den = $items.Count - [int]$c['ABANDONED']
    $pct = if ($den -gt 0) { [math]::Round(100 * [int]$c['COMPLETED'] / $den) } else { 0 }
    $detail = (@('IN PROGRESS', 'IN REVIEW', 'BLOCKED', 'FAILED', 'NOT STARTED', 'ABANDONED') | Where-Object { $c[$_] } | ForEach-Object { "$($c[$_]) $($_.ToLower())" }) -join ', '
    Write-Output ("{0}: {1}/{2} completed ({3}%){4}" -f (Get-Rel $f), [int]$c['COMPLETED'], $den, $pct, $(if ($detail) { " - $detail" } else { '' }))
    $items | Where-Object { $s = $_.Matches[0].Groups[2].Value; $s -ne 'COMPLETED' -and $s -ne 'ABANDONED' } | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
  }
}

# ---------- locks ----------
$LockTtl = if ($env:CTX_LOCK_TTL) { [int]$env:CTX_LOCK_TTL } else { 600 }
function Get-Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Get-LockFile($ctx, $name) {
  $d = Join-Path $ctx '.locks'; New-Item -ItemType Directory -Force -Path $d | Out-Null
  Join-Path $d (($name -replace '[\\/:*?"<>| ]', '_') + '.lock')
}
function Read-Lock($lf) {
  $p = (Get-Content $lf -TotalCount 1) -split '\|'
  [pscustomobject]@{ Owner = $p[0]; Age = (Get-Now) - [int64]$p[1] }
}

# ---------- doctor ----------
function Add-Issue($lvl, $loc, $msg) {
  if ($lvl -eq 'ERROR') { $script:E++ } elseif ($lvl -eq 'WARN') { $script:W++ }
  Write-Host ("{0,-5} {1}: {2}" -f $lvl, $loc, $msg)
}

function Invoke-Doctor($ctx) {
  $script:E = 0; $script:W = 0
  $today = (Get-Date).Date
  foreach ($n in 'START_HERE.md', 'STATE.md', 'goals.md', 'todo.md', 'donts.md', 'preferences.md', 'security.md', 'log.md') {
    if (-not (Test-Path (Join-Path $ctx $n))) { Add-Issue 'WARN' $n 'missing (run ctx init to restore templates)' }
  }
  foreach ($f in Get-CtxFiles $ctx) {
    $rel = Get-Rel $f
    $lines = @(Get-Content $f.FullName -Encoding UTF8)
    $seen = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $ln = $lines[$i]; $loc = "${rel}:$($i + 1)"
      if ($ln -match '^\s*-\s+\S+\s*\|') {
        if ($ln -notmatch $ItemPat) { Add-Issue 'ERROR' $loc 'malformed item line (expected: - ID | STATUS PCT% | title | date | note)'; continue }
        $m = [regex]::Match($ln, $ItemPat); $id = $m.Groups[1].Value; $st = $m.Groups[2].Value; $pct = [int]$m.Groups[3].Value
        $p = $ln -split '\|'
        if (([string]$p[2]).Trim() -match '^<[^>]*>$') { continue }
        if ($seen.ContainsKey($id)) { Add-Issue 'ERROR' $loc "duplicate ID $id" } else { $seen[$id] = 1 }
        if ($st -eq 'NOT STARTED' -and $pct -ne 0) { Add-Issue 'ERROR' $loc "$id NOT STARTED must be 0%" }
        if ($st -eq 'COMPLETED' -and $pct -ne 100) { Add-Issue 'ERROR' $loc "$id COMPLETED must be 100%" }
        if ($st -eq 'IN PROGRESS' -and ($pct -lt 1 -or $pct -gt 99)) { Add-Issue 'ERROR' $loc "$id IN PROGRESS must be 1-99%" }
        if ($pct -gt 100) { Add-Issue 'ERROR' $loc "$id percent over 100" }
        $date = ([string]$p[3]).Trim(); $note = ([string]$p[4]).Trim()
        if ($st -eq 'COMPLETED' -and (-not $date -or -not $note)) { Add-Issue 'WARN' $loc "$id COMPLETED without date/evidence" }
        if (($st -eq 'FAILED' -or $st -eq 'ABANDONED' -or $st -eq 'BLOCKED') -and -not $note) { Add-Issue 'WARN' $loc "$id $st without a reason in the note" }
        $d = [datetime]::MinValue
        if ($st -eq 'IN PROGRESS' -and [datetime]::TryParseExact($date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) {
          if (($today - $d).Days -gt 14) { Add-Issue 'WARN' $loc "$id IN PROGRESS untouched for $(($today - $d).Days) days" }
        }
      }
    }
    $limit = if ($f.Name -eq 'STATE.md') { 40 } elseif ($f.Name -eq 'log.md') { 300 } else { 400 }
    if ($lines.Count -gt $limit) { Add-Issue 'WARN' $rel "$($lines.Count) lines (budget $limit); run ctx archive or trim" }
  }
  # secrets: every markdown file in the folder, including archive
  foreach ($f in Get-ChildItem $ctx -Recurse -File | Where-Object { $_.FullName -notmatch '\\(\.git|\.locks)\\' -and $_.Length -lt 1MB -and $_.Extension -notin '.zip', '.gz', '.png', '.jpg' }) {
    $rel = Get-Rel $f; $n = 0
    foreach ($ln in (Get-Content $f.FullName -Encoding UTF8)) {
      $n++
      foreach ($pt in $SecretPats) { if ($ln -match $pt) { Add-Issue 'ERROR' "${rel}:$n" 'possible secret (value hidden). Remove it and rotate it'; break } }
    }
  }
  # locks
  $ld = Join-Path $ctx '.locks'
  if (Test-Path $ld) {
    foreach ($l in Get-ChildItem $ld -Filter *.lock -File) {
      $k = Read-Lock $l.FullName
      if ($k.Age -gt $LockTtl) { Add-Issue 'WARN' ".locks/$($l.Name)" "stale lock held by $($k.Owner) ($($k.Age)s old); remove with ctx unlock" }
      else { Add-Issue 'INFO' ".locks/$($l.Name)" "held by $($k.Owner) ($($k.Age)s)" }
    }
  }
  # STATE.md freshness
  $sp = Join-Path $ctx 'STATE.md'
  if (Test-Path $sp) {
    $mm = [regex]::Match((Get-Content $sp -Raw -Encoding UTF8), 'Last updated:\s*(\d{4}-\d{2}-\d{2})')
    $d = [datetime]::MinValue
    if ($mm.Success -and [datetime]::TryParseExact($mm.Groups[1].Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) {
      if (($today - $d).Days -gt 7) { Add-Issue 'WARN' 'STATE.md' "last updated $(($today - $d).Days) days ago" }
    } else { Add-Issue 'INFO' 'STATE.md' 'still a template (no Last updated date)' }
  }
  # token budget for the Always tier
  $chars = 0
  foreach ($n in $Always) { $p = Join-Path $ctx $n; if (Test-Path $p) { $chars += (Get-Content $p -Raw -Encoding UTF8).Length } }
  $tok = [math]::Round($chars / 4)
  $lvl = if ($tok -gt 3000) { 'WARN' } else { 'INFO' }
  Add-Issue $lvl 'budget' "Always tier is about $tok tokens (target under 3000)"
  # unfilled templates
  $un = @(Get-CtxFiles $ctx | Where-Object { $_.Name -ne 'README.md' -and (Get-Content $_.FullName -Raw -Encoding UTF8) -match '<[^>\r\n]{2,}>' } | ForEach-Object { Get-Rel $_ })
  if ($un.Count) { Add-Issue 'INFO' 'templates' "$($un.Count) file(s) still contain placeholders: $($un -join ', ')" }
  Write-Host ("doctor: {0} error(s), {1} warning(s)" -f $script:E, $script:W)
  return $script:E
}

# ---------- archive ----------
function Invoke-Archive($ctx) {
  [void](Save-Snapshot $ctx 'pre-archive')
  $keep = 15; $movedEntries = 0; $movedPlans = 0
  $log = Join-Path $ctx 'log.md'
  if (Test-Path $log) {
    $lines = @(Get-Content $log -Encoding UTF8)
    $idx = @(0..($lines.Count - 1) | Where-Object { $lines[$_] -match '^## ' })
    if ($idx.Count -gt $keep) {
      $first = $idx[0]; $cut = $idx[$idx.Count - $keep]
      $head = if ($first -gt 0) { $lines[0..($first - 1)] } else { @() }
      $old = $lines[$first..($cut - 1)]
      $new = @($head) + @($lines[$cut..($lines.Count - 1)])
      $ad = Join-Path $ctx 'archive'; New-Item -ItemType Directory -Force -Path $ad | Out-Null
      [IO.File]::AppendAllText((Join-Path $ad 'log.md'), (($old -join "`n") + "`n"), $Utf8)
      [IO.File]::WriteAllLines($log, [string[]]$new, $Utf8)
      $movedEntries = $idx.Count - $keep
    }
  }
  $pd = Join-Path $ctx 'plans'
  if (Test-Path $pd) {
    foreach ($pf in Get-ChildItem $pd -Filter *.md -File | Where-Object { $_.Name -ne '_template.md' }) {
      if (Select-String -Path $pf.FullName -Pattern '^\s*-\s+Status:\s*(COMPLETED|ABANDONED)\b' -Quiet -Encoding UTF8) {
        $ap = Join-Path $ctx 'archive\plans'; New-Item -ItemType Directory -Force -Path $ap | Out-Null
        Move-Item $pf.FullName (Join-Path $ap $pf.Name) -Force; $movedPlans++
      }
    }
  }
  [void](Save-Snapshot $ctx 'archive')
  Write-Host "Archived $movedEntries log entr$(if ($movedEntries -eq 1) { 'y' } else { 'ies' }) and $movedPlans plan(s) into .context/archive/."
}

# ---------- scan ----------
function Get-WorkspaceFiles($ws) {
  if (Test-HasGit) {
    $out = Invoke-Git $ws @('ls-files', '-co', '--exclude-standard')
    if ($script:GitOk -and $out) { return @($out) }
  }
  @(Get-ChildItem $ws -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($ws.Length + 1) -replace '\\', '/' } |
    Where-Object { ('/' + $_) -notmatch '/(node_modules|\.git|dist|build|venv|\.venv|target|vendor|\.context|__pycache__)/' })
}

function Invoke-Scan($ws, $ctx) {
  $files = Get-WorkspaceFiles $ws
  $sb = New-Object Text.StringBuilder
  function L($s) { [void]$sb.AppendLine($s) }
  L '# Scan (auto-generated, facts only)'
  L ''
  L ("Generated by ``ctx scan`` on {0}. Overwritten on every scan. Verify in the code before relying on it, then copy confirmed facts into the other files." -f (Get-Date -Format 'yyyy-MM-dd'))
  L ''; L '## Workspace'
  L ("- Name: {0}" -f (Split-Path $ws -Leaf))
  L ("- Files (excluding ignored): {0}" -f $files.Count)
  $tops = @($files | Where-Object { $_ -match '/' } | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique | Select-Object -First 25)
  if ($tops.Count) { L ("- Top-level folders: {0}" -f ($tops -join ', ')) }
  if (Test-HasGit) {
    $br = Invoke-Git $ws @('branch', '--show-current')
    if ($script:GitOk) {
      L ''; L '## Git'
      L ("- Current branch: {0}" -f $(if ($br) { $br } else { '(detached or none)' }))
      $rem = @(Invoke-Git $ws @('remote', '-v') | Where-Object { $_ -match '\(fetch\)' } | ForEach-Object { $_ -replace '//[^/@\s]+@', '//' })
      if ($rem.Count) { L ("- Remotes: {0}" -f ($rem -join '; ')) }
      $lb = @(Invoke-Git $ws @('branch', '--format=%(refname:short)') | Select-Object -First 10)
      if ($lb.Count) { L ("- Local branches: {0}" -f ($lb -join ', ')) }
    }
  }
  L ''; L '## Languages (by file extension)'
  $ext = $files | ForEach-Object { if ($_ -match '\.([A-Za-z0-9]+)$') { $matches[1].ToLower() } } | Where-Object { $_ -notin 'md', 'json', 'lock', 'txt', 'svg', 'png', 'jpg', 'ico', 'map' } | Group-Object | Sort-Object Count -Descending | Select-Object -First 8
  foreach ($e in $ext) { L ("- .{0}: {1}" -f $e.Name, $e.Count) }
  L ''; L '## Manifests and stack hints'
  $mf = @{ 'package.json' = 'Node/JS'; 'pyproject.toml' = 'Python'; 'requirements.txt' = 'Python'; 'Pipfile' = 'Python'; 'go.mod' = 'Go'; 'Cargo.toml' = 'Rust'; 'pom.xml' = 'Java (Maven)'; 'build.gradle' = 'Java/Kotlin (Gradle)'; 'Gemfile' = 'Ruby'; 'composer.json' = 'PHP'; 'mix.exs' = 'Elixir'; 'deno.json' = 'Deno'; 'tsconfig.json' = 'TypeScript' }
  $blob = ''
  foreach ($k in ($mf.Keys | Sort-Object)) {
    $hit = @($files | Where-Object { $_ -eq $k -or $_ -like "*/$k" } | Select-Object -First 5)
    if ($hit.Count) { L ("- {0} ({1}): {2}" -f $k, $mf[$k], ($hit -join ', ')); $root = Join-Path $ws $hit[0]; if (Test-Path $root) { $blob += "`n" + (Get-Content $root -Raw -ErrorAction SilentlyContinue) } }
  }
  $csp = @($files | Where-Object { $_ -match '\.(csproj|sln)$' } | Select-Object -First 5); if ($csp.Count) { L ("- .NET: {0}" -f ($csp -join ', ')) }
  $tokens = 'next', 'react', 'vue', 'svelte', 'angular', 'express', 'fastify', 'nestjs', 'vite', 'tailwindcss', 'prisma', 'drizzle-orm', 'django', 'flask', 'fastapi', 'rails', 'laravel', 'spring-boot', 'gin-gonic', 'axum', 'actix'
  $fw = @($tokens | Where-Object { $blob -match "(?i)(^|[^a-z0-9_-])$([regex]::Escape($_))([^a-z0-9_-]|$)" })
  if ($fw.Count) { L ("- Framework/library hints (verify): {0}" -f ($fw -join ', ')) }
  $pj = Join-Path $ws 'package.json'
  if (Test-Path $pj) {
    try {
      $j = Get-Content $pj -Raw | ConvertFrom-Json
      if ($j.scripts) { L ''; L '## package.json scripts'; foreach ($p in $j.scripts.PSObject.Properties) { L ("- {0}: ``{1}``" -f $p.Name, $p.Value) } }
    } catch {}
  }
  L ''; L '## CI, infrastructure and security files'
  $pats = [ordered]@{
    'Dockerfile' = '(^|/)Dockerfile'; 'docker-compose' = 'docker-compose.*\.ya?ml$'; 'GitHub Actions' = '^\.github/workflows/'; 'GitLab CI' = '\.gitlab-ci\.yml$'
    'Vercel' = '(^|/)vercel\.json$'; 'Netlify' = '(^|/)netlify\.toml$'; 'Cloudflare (wrangler)' = '(^|/)wrangler\.(toml|jsonc?)$'; 'Fly.io' = '(^|/)fly\.toml$'
    'Render' = '(^|/)render\.yaml$'; 'Procfile' = '(^|/)Procfile$'; 'Terraform' = '\.tf$'; 'Kubernetes/Helm' = '(^|/)(k8s|helm|charts)/'; 'Serverless' = '(^|/)serverless\.ya?ml$'
    'env example' = '(^|/)\.env(\.[a-z]+)?\.(example|sample)$'; 'CODEOWNERS' = '(^|/)CODEOWNERS$'; 'SECURITY.md' = '(^|/)SECURITY\.md$'; 'CONTRIBUTING.md' = '(^|/)CONTRIBUTING\.md$'
    'pre-commit' = '\.pre-commit-config\.yaml$'; 'Dependabot/Renovate' = '(dependabot\.ya?ml|renovate\.json)$'
    'Lint/format config' = '(^|/)(\.eslintrc.*|eslint\.config\..*|\.prettierrc.*|ruff\.toml|\.golangci\.ya?ml|rustfmt\.toml|\.editorconfig)$'
    'Tests' = '(^|/)(tests?|__tests__|spec|e2e)/'
  }
  foreach ($k in $pats.Keys) {
    $hit = @($files | Where-Object { $_ -match $pats[$k] })
    if ($hit.Count) { L ("- {0}: {1}{2}" -f $k, (($hit | Select-Object -First 3) -join ', '), $(if ($hit.Count -gt 3) { " (+$($hit.Count - 3) more)" } else { '' })) }
  }
  $envf = @($files | Where-Object { $_ -match '(^|/)\.env$' })
  if ($envf.Count) { L ''; L ("- WARNING: .env file(s) not ignored by git: {0}. Add them to .gitignore." -f ($envf -join ', ')) }
  [IO.File]::WriteAllText((Join-Path $ctx 'scan.md'), $sb.ToString(), $Utf8)
}

# ---------- commands ----------
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
      if (Test-Path $pf) { Add-Content $pf "`n$block" } else { [IO.File]::WriteAllText($pf, $block, $Utf8) }
      if (-not (Test-Tracked $ws $p)) { [void](Add-Exclude $ws $p) }
      else { Write-Warning "$p is tracked by git; the pointer block was added but will show up as a change." }
    }
    Invoke-Scan $ws $ctx
    $snap = Save-Snapshot $ctx 'ctx init'
    Write-Host "Context ready: $ctx ($created new files)"
    if ($ex) { Write-Host 'Excluded via .git/info/exclude (local only, nothing committed).' }
    else { Write-Host "Not a git repo (or git missing): nothing to exclude yet. Re-run init after 'git init'." }
    if ($snap) { Write-Host 'Snapshot history started (ctx history).' }
    Write-Host "Repo facts written to .context/scan.md.`n`nNext, paste this into ANY agent/harness (or put it in its instruction file):`n  $bootstrap`nTo have the agent fill the files from this repo, run: ctx bootstrap"
  }
  'status' {
    $ctx = Get-Ctx $Path
    Get-Content (Join-Path $ctx 'STATE.md') -Encoding UTF8
    Write-Output "`n--- Progress ---"
    Show-Progress $ctx
  }
  'brief' {
    $ctx = Get-Ctx $Path; $ws = Split-Path $ctx
    $br = if (Test-HasGit) { Invoke-Git $ws @('branch', '--show-current') } else { '' }
    Write-Output ("# Local context brief: {0}{1}" -f (Split-Path $ws -Leaf), $(if ($br) { " (branch $br)" } else { '' }))
    Write-Output 'Full protocol: .context/START_HERE.md. Read other files only when relevant.'
    if (Test-Path (Join-Path $ws 'team-context')) { Write-Output 'Team rules: read team-context/ first (committed, shared, wins over personal context).' }
    foreach ($n in $Always) { $p = Join-Path $ctx $n; if (Test-Path $p) { Write-Output "`n## .context/$n"; Get-Content $p -Encoding UTF8 } }
    Write-Output "`n## Progress"
    Show-Progress $ctx
    Write-Output "`nBefore finishing: update item statuses, STATE.md and log.md, then run: ctx wrap"
  }
  'doctor' { $ctx = Get-Ctx $Path; $e = Invoke-Doctor $ctx; if ($e -gt 0) { exit 1 } }
  'wrap' {
    $ctx = Get-Ctx $Path
    $e = Invoke-Doctor $ctx
    if (Save-Snapshot $ctx 'ctx wrap') { Write-Host 'Snapshot saved.' } else { Write-Host 'No changes to snapshot.' }
    if ($e -gt 0) { Write-Host 'Fix the errors above, then run ctx wrap again.'; exit 1 }
  }
  'archive' { Invoke-Archive (Get-Ctx $Path) }
  'scan' { $ctx = Get-Ctx $Path; Invoke-Scan (Split-Path $ctx) $ctx; Write-Host 'Wrote .context/scan.md' }
  'bootstrap' {
    $ctx = Get-Ctx $Path; Invoke-Scan (Split-Path $ctx) $ctx
    Write-Host @'
Paste this to your agent:

Bootstrap this workspace's local context. Read .context/START_HERE.md and .context/scan.md. Verify the scan's facts in the code. Then fill in architecture.md, conventions.md, deployment.md, infrastructure.md and security.md (derive security practices from the stack), design.md if there is a UI, and STATE.md and goals.md after asking me at most five short questions. Do not invent facts: write "unknown" where you cannot tell. When done, run ctx doctor if available and show me a summary of what you filled in and what is still unknown.
'@
  }
  'snapshot' {
    $ctx = Get-Ctx $Path
    $msg = if ($Extra) { $Extra } else { 'manual snapshot' }
    if (Save-Snapshot $ctx $msg) { Write-Host "Snapshot saved: $msg" } else { Write-Host 'No changes (or git missing).' }
  }
  'history' { $ctx = Get-Ctx $Path; Invoke-Git $ctx @('log', '--oneline', '-n', '30') }
  'restore' {
    $ctx = Get-Ctx '.'
    if ($Path -eq '.') { Write-Host 'Usage: ctx restore <file> [rev]   (run in the workspace; see ctx history)'; exit 1 }
    $rev = if ($Extra) { $Extra } else { 'HEAD' }
    if ($Extra) { [void](Save-Snapshot $ctx 'pre-restore') }   # restoring HEAD discards edits made since the last snapshot
    [void](Invoke-Git $ctx @('checkout', $rev, '--', $Path))
    if ($script:GitOk) { Write-Host "Restored $Path from $rev." } else { Write-Host "Could not restore $Path from $rev."; exit 1 }
  }
  'backup' {
    $ctx = Get-Ctx $Path; $ws = Split-Path $ctx
    $dest = $Extra
    if (-not $dest) {
      $dir = Join-Path $HOME '.local-context-backups'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
      $dest = Join-Path $dir ("{0}-{1}.zip" -f (Split-Path $ws -Leaf), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    Compress-Archive -Path $ctx -DestinationPath $dest -Force
    Write-Host "Backup written: $dest"
  }
  'team' {
    $ws = (Resolve-Path $Path).Path; $td = Join-Path $ws 'team-context'
    New-Item -ItemType Directory -Force -Path $td | Out-Null
    $tt = Join-Path $self 'team-templates'
    foreach ($pair in @(@((Join-Path $tt 'README.md'), 'README.md'), @((Join-Path $src 'workflow.md'), 'workflow.md'), @((Join-Path $src 'security.md'), 'security.md'), @((Join-Path $src 'conventions.md'), 'conventions.md'))) {
      $d = Join-Path $td $pair[1]; if (-not (Test-Path $d)) { Copy-Item $pair[0] $d }
    }
    Write-Host "Created $td. Review it, then commit it: it is shared with your team (unlike .context/)."
  }
  'lock' {
    $ctx = Get-Ctx '.'
    if ($Path -eq '.') { Write-Host 'Usage: ctx lock <file> [owner]   (run in the workspace)'; exit 1 }
    $owner = if ($Extra) { $Extra } else { $env:USERNAME }
    $lf = Get-LockFile $ctx $Path; $now = Get-Now
    if (Test-Path $lf) {
      $k = Read-Lock $lf
      if ($k.Owner -ne $owner -and $k.Age -lt $LockTtl) { Write-Host "$Path is locked by $($k.Owner) ($($k.Age)s ago). Wait, or ask them to run: ctx unlock $Path"; exit 1 }
      Remove-Item $lf -Force
    }
    try { $fs = [IO.File]::Open($lf, 'CreateNew', 'Write', 'None'); $b = $Utf8.GetBytes("$owner|$now`n"); $fs.Write($b, 0, $b.Length); $fs.Close() }
    catch { Write-Host "$Path was just locked by someone else."; exit 1 }
    Write-Host "Locked $Path for $owner (stale after ${LockTtl}s; re-run to refresh). Release with: ctx unlock $Path"
  }
  'unlock' {
    $ctx = Get-Ctx '.'
    if ($Path -eq '.') { Write-Host 'Usage: ctx unlock <file> [owner]   (-Yes forces)'; exit 1 }
    $lf = Get-LockFile $ctx $Path
    if (-not (Test-Path $lf)) { Write-Host "$Path is not locked."; break }
    $k = Read-Lock $lf
    if ($Yes -or -not $Extra -or $k.Owner -eq $Extra) { Remove-Item $lf -Force; Write-Host "Unlocked $Path." }
    else { Write-Host "$Path is locked by $($k.Owner). Use -Yes to force."; exit 1 }
  }
  'locks' {
    $ctx = Get-Ctx $Path; $ld = Join-Path $ctx '.locks'
    $ls = @(); if (Test-Path $ld) { $ls = @(Get-ChildItem $ld -Filter *.lock -File) }
    if (-not $ls.Count) { Write-Host 'No locks held.' }
    foreach ($l in $ls) { $k = Read-Lock $l.FullName; Write-Host ("{0}: {1} ({2}s{3})" -f ($l.BaseName), $k.Owner, $k.Age, $(if ($k.Age -gt $LockTtl) { ', STALE' } else { '' })) }
  }
  'log' {
    $ctx = Get-Ctx '.'; $ws = Split-Path $ctx
    if ($Path -eq '.') { Write-Host 'Usage: ctx log "<what happened>" [who]   (run in the workspace)'; exit 1 }
    $br = if (Test-HasGit) { Invoke-Git $ws @('branch', '--show-current') } else { '' }
    $who = if ($Extra) { $Extra } else { $env:USERNAME }
    $entry = "`n## $(Get-Date -Format 'yyyy-MM-dd') - $Path`n- Branch: $(if ($br) { $br } else { 'n/a' })`n- By: $who`n"
    for ($i = 0; $i -lt 5; $i++) { try { [IO.File]::AppendAllText((Join-Path $ctx 'log.md'), $entry, $Utf8); break } catch { Start-Sleep -Milliseconds 100 } }
    Write-Host 'Appended to log.md.'
  }
  'agents' {
    $ws = (Resolve-Path '.').Path; $td = Join-Path $ws 'team-context'
    if (-not (Test-Path $td)) { Write-Host 'No team-context/. Run: ctx team'; exit 1 }
    $target = if ($Path -ne '.') { $Path } else { 'AGENTS.md' }
    $out = New-Object Collections.Generic.List[string]
    foreach ($f in Get-ChildItem $td -Filter *.md -File | Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name) {
      $tpl = Join-Path $src $f.Name
      if ((Test-Path $tpl) -and ((Get-Content $f.FullName -Raw).Replace("`r`n", "`n") -eq (Get-Content $tpl -Raw).Replace("`r`n", "`n"))) { continue }
      $ls = @(Get-Content $f.FullName -Encoding UTF8 | Where-Object { $_ -notmatch '<[^>]{2,}>' })
      for ($i = 0; $i -lt $ls.Count; $i++) {
        $l = $ls[$i]
        if ($l -match '^#+ ') {
          $j = $i + 1; while ($j -lt $ls.Count -and $ls[$j] -match '^\s*$') { $j++ }
          if ($j -ge $ls.Count -or $ls[$j] -match '^#+ ') { continue }
          $l = $l -replace '^(#+)', '$1#'
        }
        if ($l -match '^\s*$' -and ($out.Count -eq 0 -or $out[$out.Count - 1] -match '^\s*$')) { continue }
        $out.Add($l)
      }
      if ($out.Count -and $out[$out.Count - 1] -notmatch '^\s*$') { $out.Add('') }
    }
    if (-not (($out -join '').Trim())) { Write-Host 'team-context/ is still a template. Fill it in first.'; exit 1 }
    $block = "<!-- team-context:start -->`n<!-- Generated by ctx agents from team-context/. Edit there, then re-run. -->`n## Team rules`n" + ($out -join "`n").TrimEnd() + "`n<!-- team-context:end -->`n"
    $tp = Join-Path $ws $target
    if ((Test-Path $tp) -and ((Get-Content $tp -Raw) -match 'team-context:start')) {
      $new = [regex]::Replace((Get-Content $tp -Raw), '(?s)<!-- team-context:start -->.*?<!-- team-context:end -->\r?\n?', $block.Replace('$', '$$'))
      [IO.File]::WriteAllText($tp, $new, $Utf8)
    } elseif (Test-Path $tp) { [IO.File]::AppendAllText($tp, "`n$block", $Utf8) }
    else { [IO.File]::WriteAllText($tp, $block, $Utf8) }
    Write-Host "Wrote team rules into $target. Review and commit it: unlike .context/, it is shared."
  }
  'hooks' {
    $sub = $Path
    switch ($sub) {
      'git' {
        $ws = (Resolve-Path $(if ($Extra) { $Extra } else { '.' })).Path
        $hd = Invoke-Git $ws @('rev-parse', '--git-path', 'hooks')
        if (-not $script:GitOk -or -not $hd) { Write-Host 'Not a git repo.'; exit 1 }
        if (-not [IO.Path]::IsPathRooted($hd)) { $hd = Join-Path $ws $hd }
        New-Item -ItemType Directory -Force -Path $hd | Out-Null
        $hf = Join-Path $hd 'post-commit'
        $block = "# local-context:start`nif command -v ctx >/dev/null 2>&1; then ctx snapshot . ""after commit"" >/dev/null 2>&1 || true`nelif command -v ctx.cmd >/dev/null 2>&1; then ctx.cmd snapshot . ""after commit"" >/dev/null 2>&1 || true; fi`n# local-context:end`n"
        if ((Test-Path $hf) -and ((Get-Content $hf -Raw) -match 'local-context:start')) { Write-Host 'post-commit hook already installed.'; break }
        if (Test-Path $hf) { [IO.File]::AppendAllText($hf, "`n$block", $Utf8) } else { [IO.File]::WriteAllText($hf, "#!/bin/sh`n$block", $Utf8) }
        Write-Host "Installed post-commit hook ($hf): saves a .context snapshot after each commit. Local only, never committed."
      }
      'git-remove' {
        $ws = (Resolve-Path $(if ($Extra) { $Extra } else { '.' })).Path
        $hd = Invoke-Git $ws @('rev-parse', '--git-path', 'hooks')
        if (-not [IO.Path]::IsPathRooted($hd)) { $hd = Join-Path $ws $hd }
        $hf = Join-Path $hd 'post-commit'
        if (-not (Test-Path $hf)) { Write-Host 'No post-commit hook.'; break }
        $t = [regex]::Replace((Get-Content $hf -Raw), '(?s)\r?\n?# local-context:start.*?# local-context:end\r?\n?', '')
        if (($t -replace '#!/bin/sh', '').Trim()) { [IO.File]::WriteAllText($hf, $t, $Utf8) } else { Remove-Item $hf -Force }
        Write-Host 'Removed the local-context post-commit hook.'
      }
      'claude' {
        Write-Host @'
Claude Code: make every session start with the context brief. Add this to .claude/settings.local.json (this project, not committed) or ~/.claude/settings.json (all projects), merging with any existing "hooks":

{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "ctx brief" } ] }
    ]
  }
}

Per the hooks docs, a SessionStart hook's plain-text stdout is added to Claude's context. Add "matcher": "startup" to the group to skip resume/clear/compact. There is no Stop hook here on purpose: plain stdout from Stop does not reach the model. Run ctx wrap yourself, or install the git hook: ctx hooks git
'@
      }
      default { Write-Host 'Usage: ctx hooks <git|git-remove|claude> [workspace]' }
    }
  }
  'upgrade' {
    $ctx = Get-Ctx $Path
    Copy-Item (Join-Path $src 'START_HERE.md') (Join-Path $ctx 'START_HERE.md') -Force
    Get-ChildItem $src -Recurse -File | ForEach-Object {
      $dest = Join-Path $ctx ($_.FullName.Substring($src.Length).TrimStart('\', '/'))
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
      if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest; Write-Host "Added $($dest.Substring($ctx.Length + 1))" }
    }
    [void](Save-Snapshot $ctx 'ctx upgrade')
    Write-Host 'START_HERE.md refreshed; missing files added.'
  }
  'version' { Write-Host ("ctx {0}" -f $(if (Test-Path (Join-Path $self 'VERSION')) { (Get-Content (Join-Path $self 'VERSION') -TotalCount 1).Trim() } else { 'dev' })) }
  'update' {
    $rf = Join-Path $self 'repo.txt'
    if (-not (Test-Path $rf)) { Write-Host 'No repo.txt: installed from a clone? Use git pull there.'; break }
    $r = Get-Content $rf
    if ($Path -ne '.') { $env:CTX_REF = $Path }
    $env:CTX_REPO = $r[0]; $env:CTX_BRANCH = $r[1]
    Invoke-RestMethod "https://raw.githubusercontent.com/$($r[0])/$(if ($Path -ne '.') { $Path } else { $r[1] })/install.ps1" | Invoke-Expression
  }
  'uninstall' {
    $expected = Join-Path $HOME '.local-context'
    if ($self -ne $expected) { Write-Host "Refusing: this copy ($self) is not the installed one ($expected)."; break }
    if (-not $Yes) { Write-Host "Would remove $self and its PATH entry. Workspace .context folders are untouched. Re-run with -Yes to confirm."; break }
    $up = [Environment]::GetEnvironmentVariable('Path', 'User')
    $np = (($up -split ';') | Where-Object { $_ -and $_ -ne $self }) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $np, 'User')
    Remove-Item $self -Recurse -Force
    Write-Host 'ctx removed. Open a new terminal. Your workspace .context folders were not touched.'
  }
  default {
    Write-Host @'
Usage: ctx <command> [path]
  init [path] [-Pointer f1,f2]  create .context/, scan repo, hide from git
  status | brief | doctor | wrap | archive | scan | bootstrap | team
  snapshot [path] [message] | history | backup [path] [dest.zip]
  restore <file> [rev]          restore a file from history (run in the workspace)
  lock <file> [owner] | unlock <file> [owner] | locks    short leases for shared files (parallel agents)
  log "<what happened>" [who]   append an entry to log.md safely
  agents [file]                 export team-context/ into a committable AGENTS.md block
  hooks <git|git-remove|claude> install the git snapshot hook / print the Claude Code hook
  upgrade                       refresh the protocol, add missing templates
  update [ref]                  update ctx (latest release, or tag/branch/sha)
  uninstall -Yes | version
'@
  }
}
