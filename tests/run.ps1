# Tests for ctx.ps1. Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1
$ErrorActionPreference = 'Stop'
$ctx = Join-Path (Split-Path -Parent $PSScriptRoot) 'ctx.ps1'
$script:fail = 0
function Check($name, $cond) { if ($cond) { Write-Host "PASS $name" } else { Write-Host "FAIL $name"; $script:fail++ } }
function Run { & powershell -NoProfile -ExecutionPolicy Bypass -File $ctx @args 2>&1 | Out-String }
function RunCode { & powershell -NoProfile -ExecutionPolicy Bypass -File $ctx @args *>&1 | Out-Null; $LASTEXITCODE }

$t = Join-Path ([IO.Path]::GetTempPath()) ('ctxt-' + [guid]::NewGuid())
New-Item -ItemType Directory $t | Out-Null
$oldEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; git -C $t init -q 2>$null; $ErrorActionPreference = $oldEap
$ws = $t

$out = Run init $ws -Pointer AGENTS.md
foreach ($n in 'START_HERE.md', 'STATE.md', 'security.md', 'workflow.md', 'infrastructure.md', 'scan.md') { Check "init creates $n" (Test-Path "$ws\.context\$n") }
$st = (git -C $ws status --short) -join ' '
Check 'init leaves git status clean of .context/AGENTS.md' ($st -notmatch 'context|AGENTS')
$bytes = [IO.File]::ReadAllBytes("$ws\AGENTS.md")
Check 'pointer file has no BOM' (-not ($bytes[0] -eq 0xEF))
Check 'pointer file has marker' ((Get-Content "$ws\AGENTS.md" -Raw) -match 'local-context:start')
Check 'history has init snapshot' ((Run history $ws) -match 'ctx init')

Set-Content "$ws\package.json" '{"dependencies":{"next":"14"},"scripts":{"dev":"next dev"}}'
[void](Run scan $ws)
$scan = Get-Content "$ws\.context\scan.md" -Raw -Encoding UTF8
Check 'scan detects framework hint' ($scan -match 'next')
Check 'scan lists scripts' ($scan -match 'dev')

Check 'doctor passes on fresh workspace' ((RunCode doctor $ws) -eq 0)

Set-Content "$ws\.context\plans\2026-01-01-p.md" "- Status: IN PROGRESS`n- T1 | COMPLETED 100% | A | 2026-01-01 | ok`n- T2 | IN PROGRESS 50% | B | $((Get-Date).ToString('yyyy-MM-dd')) | x`n- T3 | NOT STARTED 0% | C"
$s = Run status $ws
Check 'status shows 1/3 completed (33%)' ($s -match '1/3 completed \(33%\)')
Check 'brief includes STATE' ((Run brief $ws) -match 'STATE.md')

$bad = 'AK' + 'IA' + 'ABCDEFGHIJKLMNOP'
Add-Content "$ws\.context\gotchas.md" "key $bad`n- T1 | COMPLETED 90% | dup and bad pct"
$d = Run doctor $ws
Check 'doctor flags secret' ($d -match 'possible secret')
Check 'doctor flags bad percent' ($d -match 'COMPLETED must be 100%')
Check 'doctor exits non-zero on errors' ((RunCode doctor $ws) -eq 1)
$secretBlocked = ($d -notmatch [regex]::Escape($bad))
Check 'doctor never prints the secret' $secretBlocked

Set-Content "$ws\.context\gotchas.md" '# Gotchas'
1..20 | ForEach-Object { Add-Content "$ws\.context\log.md" "`n## 2026-01-$('{0:00}' -f $_) - e$_`n- Done: x" }
Set-Content "$ws\.context\plans\2026-01-02-done.md" "- Status: COMPLETED"
[void](Run archive $ws)
Check 'archive keeps 15 log entries' (@(Select-String -Path "$ws\.context\log.md" -Pattern '^## ').Count -eq 15)
Check 'archive moves finished plan' (Test-Path "$ws\.context\archive\plans\2026-01-02-done.md")

Add-Content "$ws\.context\donts.md" 'OOPS'
Push-Location $ws; [void](Run restore donts.md); Pop-Location
Check 'restore reverts a file' (-not ((Get-Content "$ws\.context\donts.md" -Raw) -match 'OOPS'))

Add-Content "$ws\.context\goals.md" 'MY NOTE'
[void](Run init $ws)
Check 're-running init keeps notes' ((Get-Content "$ws\.context\goals.md" -Raw) -match 'MY NOTE')

$zip = Join-Path ([IO.Path]::GetTempPath()) ('ctxb-' + [guid]::NewGuid() + '.zip')
[void](Run backup $ws $zip)
Check 'backup writes archive' ((Test-Path $zip) -and (Get-Item $zip).Length -gt 0)
[void](Run team $ws)
Check 'team creates team-context' (Test-Path "$ws\team-context\workflow.md")

Push-Location $ws
Check 'agents refuses an unfilled team-context' ((RunCode agents) -ne 0)
Set-Content "$ws\team-context\workflow.md" "# Workflow`n`n## Branching`n- Branch from main." -Encoding utf8
[void](Run agents); [void](Run agents)
Check 'agents exports team rules idempotently' (((Get-Content "$ws\AGENTS.md" -Raw) -match 'Branch from main') -and (@(Select-String "$ws\AGENTS.md" -Pattern 'team-context:start').Count -eq 1))
[void](Run lock STATE.md agentA)
Check 'lock blocks a second owner' ((RunCode lock STATE.md agentB) -ne 0)
$env:CTX_LOCK_TTL = '0'; $dd = Run doctor; Remove-Item Env:\CTX_LOCK_TTL
Check 'doctor reports stale locks' ($dd -match 'stale lock')
[void](Run unlock STATE.md agentA)
Check 'unlock releases the lock' (-not (Test-Path "$ws\.context\.locks\STATE.md.lock"))
[void](Run log 'test entry' bot)
Check 'log appends an entry' ((Get-Content "$ws\.context\log.md" -Raw) -match 'test entry')
[void](Run hooks git)
Check 'hooks git installs post-commit' ((Get-Content "$ws\.git\hooks\post-commit" -Raw) -match 'local-context:start')
[void](Run hooks git-remove)
Check 'hooks git-remove removes it' (-not (Test-Path "$ws\.git\hooks\post-commit"))
Check 'hooks claude prints the SessionStart config' ((Run hooks claude) -match 'SessionStart')
Pop-Location

if ((Get-Command sh -ErrorAction SilentlyContinue) -and -not $env:CTX_SKIP_EVALS) {
  $runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'evals/run.sh'
  $g = (& sh $runner --agent 'sh "$EVALS_DIR/mocks/good.sh"' 2>&1 | Out-String)
  $b = (& sh $runner --agent 'sh "$EVALS_DIR/mocks/bad.sh"' 2>&1 | Out-String)
  Check 'eval runner: good mock passes all with context' ($g -match 'SUMMARY with pass=6 fail=0')
  Check 'eval runner: bad mock fails all with context' ($b -match 'SUMMARY with pass=0 fail=6')
}
Check 'uninstall refuses on a non-installed copy' ((Run uninstall -Yes) -match 'Refusing')
Check 'version prints' ((Run version) -match 'ctx \d')
if (Get-Command node -ErrorAction SilentlyContinue) {
  $root = Split-Path -Parent $PSScriptRoot
  Check 'npm launcher runs ctx' ((& node (Join-Path $root 'bin\ctx.js') version 2>&1 | Out-String) -match 'ctx \d')
  $pv = (& node -p "require('$($root -replace '\\', '/')/package.json').version" | Out-String).Trim()
  Check 'package.json version matches VERSION' ($pv -eq (Get-Content (Join-Path $root 'VERSION') -TotalCount 1).Trim())
  Check 'npm launcher handles update' ((& node (Join-Path $root 'bin\ctx.js') update 2>&1 | Out-String) -match 'installed with npm')
  [void](Run init $ws -Pointer 'X1.md,X2.md')
  Check 'comma-separated -Pointer creates both files' ((Test-Path "$ws\X1.md") -and (Test-Path "$ws\X2.md"))
}

Remove-Item $t, $zip -Recurse -Force -ErrorAction SilentlyContinue
if ($script:fail) { Write-Host "$script:fail test(s) failed"; exit 1 } else { Write-Host 'All tests passed'; exit 0 }
