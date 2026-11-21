#!/usr/bin/env node
'use strict';
// Thin launcher: runs ctx.ps1 on Windows and ctx.sh everywhere else. The scripts are the source of truth.
const { spawnSync } = require('child_process');
const path = require('path');

const root = path.join(__dirname, '..');
const args = process.argv.slice(2);

if (args[0] === 'update' || args[0] === 'uninstall') {
  console.log([
    'This copy was installed with npm.',
    '  update:    npm install -g @coosley/local-context@latest   (or run: npx @coosley/local-context@latest <command>)',
    '  uninstall: npm uninstall -g @coosley/local-context',
    'Your workspace .context folders are never touched.'
  ].join('\n'));
  process.exit(0);
}

const isWin = process.platform === 'win32';
const result = isWin
  ? spawnSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(root, 'ctx.ps1'), ...args], { stdio: 'inherit' })
  : spawnSync('sh', [path.join(root, 'ctx.sh'), ...args], { stdio: 'inherit' });

if (result.error) {
  console.error(result.error.code === 'ENOENT' ? (isWin ? 'PowerShell was not found on PATH.' : 'sh was not found on PATH.') : String(result.error));
  process.exit(1);
}
process.exit(result.status === null ? 1 : result.status);
