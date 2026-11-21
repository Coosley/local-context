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
Check 'uninstall refuses on a non-installed copy' ((Run uninstall -Yes) -match 'Refusing')
Check 'version prints' ((Run version) -match 'ctx \d')

Remove-Item $t, $zip -Recurse -Force -ErrorAction SilentlyContinue
if ($script:fail) { Write-Host "$script:fail test(s) failed"; exit 1 } else { Write-Host 'All tests passed'; exit 0 }
