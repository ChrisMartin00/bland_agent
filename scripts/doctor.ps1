$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EnvFile = Join-Path $Root '.env'
if (Test-Path $EnvFile) {
  Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^(\w+)=(.*)$') {
      [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
  }
}

$requiredCmds = @('curl','codex')
foreach ($cmd in $requiredCmds) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Missing command: $cmd" }
}

$requiredEnv = @('BLAND_API_KEY','PATHWAY_ID','TEST_PHONE_NUMBER')
foreach ($name in $requiredEnv) {
  if (-not $env:$name) { throw "Missing env: $name" }
}

$requiredFiles = @(
  'AGENTS.md',
  '.codex/config.toml',
  'requests/bland/update_pathway.json',
  'requests/tests/test_call.json'
)
foreach ($file in $requiredFiles) {
  $path = Join-Path $Root $file
  if (-not (Test-Path $path)) { throw "Missing file: $file" }
}

Write-Host 'Doctor check passed.'
