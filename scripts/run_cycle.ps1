param(
  [ValidateSet('once','loop')]
  [string]$Mode = 'once'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Responses = Join-Path $Root 'responses'
$Archive = Join-Path $Responses 'archive'
New-Item -ItemType Directory -Force -Path $Archive | Out-Null

$EnvFile = Join-Path $Root '.env'
if (Test-Path $EnvFile) {
  Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^(\w+)=(.*)$') {
      [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
  }
}

if (-not $env:BLAND_BASE_URL) { $env:BLAND_BASE_URL = 'https://api.bland.ai/v1' }
if (-not $env:MAX_ITERATIONS) { $env:MAX_ITERATIONS = '10' }
if (-not $env:SLEEP_SECONDS) { $env:SLEEP_SECONDS = '5' }
if (-not $env:CODEX_CMD) { $env:CODEX_CMD = 'codex' }
if (-not $env:INBOUND_UPDATE_METHOD) { $env:INBOUND_UPDATE_METHOD = 'POST' }

function Save-Archive([string]$Path) {
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  Copy-Item $Path (Join-Path $Archive ("${stamp}_" + [IO.Path]::GetFileName($Path))) -Force
}

function Invoke-JsonApi([string]$Method, [string]$Url, [string]$BodyPath, [string]$OutPath) {
  $headers = @(
    "authorization: $($env:BLAND_API_KEY)",
    'Content-Type: application/json'
  )
  $args = @('-sS','-X',$Method)
  foreach ($h in $headers) { $args += @('-H',$h) }
  $args += @($Url,'--data',"@$BodyPath")
  & curl @args | Set-Content -Encoding UTF8 $OutPath
}

function Invoke-GetApi([string]$Url, [string]$OutPath) {
  $headers = @(
    "authorization: $($env:BLAND_API_KEY)",
    'Content-Type: application/json'
  )
  $args = @('-sS')
  foreach ($h in $headers) { $args += @('-H',$h) }
  $args += $Url
  & curl @args | Set-Content -Encoding UTF8 $OutPath
}

function Run-CodexPatch {
  Push-Location $Root
  try {
    $prompt = Get-Content (Join-Path $Root 'prompts/codex_task.txt') -Raw
    & $env:CODEX_CMD -C . $prompt
  } finally {
    Pop-Location
  }
}

function Apply-Update {
  $out = Join-Path $Responses 'update_pathway_response.json'
  Invoke-JsonApi 'POST' "$($env:BLAND_BASE_URL)/pathway/$($env:PATHWAY_ID)" (Join-Path $Root 'requests/bland/update_pathway.json') $out
  Save-Archive $out
}

function Create-Version {
  $out = Join-Path $Responses 'create_version_response.json'
  Invoke-JsonApi 'POST' "$($env:BLAND_BASE_URL)/pathway/$($env:PATHWAY_ID)/version" (Join-Path $Root 'requests/bland/create_version.json') $out
  Save-Archive $out
  $json = Get-Content $out -Raw | ConvertFrom-Json
  $version = $null
  if ($json.data.version_number) { $version = $json.data.version_number }
  elseif ($json.version_number) { $version = $json.version_number }
  elseif ($json.data.new_version_number) { $version = $json.data.new_version_number }
  if (-not $version) { throw 'Could not parse version number.' }
  $pubPath = Join-Path $Root 'requests/bland/publish_version.json'
  $pub = Get-Content $pubPath -Raw | ConvertFrom-Json
  $pub.version_id = [int]$version
  $pub | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $pubPath
  Set-Content -Encoding UTF8 (Join-Path $Responses 'latest_version_number.txt') $version
}

function Publish-Version {
  $out = Join-Path $Responses 'publish_response.json'
  Invoke-JsonApi 'POST' "$($env:BLAND_BASE_URL)/pathway/$($env:PATHWAY_ID)/publish" (Join-Path $Root 'requests/bland/publish_version.json') $out
  Save-Archive $out
}

function Link-Inbound {
  if (-not $env:INBOUND_NUMBER) { return }
  $path = Join-Path $Root 'requests/bland/link_inbound_number.json'
  $json = Get-Content $path -Raw | ConvertFrom-Json
  $json.pathway_id = $env:PATHWAY_ID
  $json | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $path
  $out = Join-Path $Responses 'link_inbound_response.json'
  Invoke-JsonApi $env:INBOUND_UPDATE_METHOD "$($env:BLAND_BASE_URL)/inbound/$($env:INBOUND_NUMBER)" $path $out
  Save-Archive $out
}

function Place-TestCall {
  $path = Join-Path $Root 'requests/tests/test_call.json'
  $json = Get-Content $path -Raw | ConvertFrom-Json
  $json.phone_number = $env:TEST_PHONE_NUMBER
  $json.pathway_id = $env:PATHWAY_ID
  $json | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $path
  $out = Join-Path $Responses 'test_call_create.json'
  Invoke-JsonApi 'POST' "$($env:BLAND_BASE_URL)/calls" $path $out
  Save-Archive $out
  $resp = Get-Content $out -Raw | ConvertFrom-Json
  $callId = $resp.call_id
  if (-not $callId -and $resp.data.call_id) { $callId = $resp.data.call_id }
  if (-not $callId) { throw 'Could not parse call_id.' }
  Set-Content -Encoding UTF8 (Join-Path $Responses 'latest_call_id.txt') $callId
}

function Fetch-CallResult {
  $callId = Get-Content (Join-Path $Responses 'latest_call_id.txt') -Raw
  $out = Join-Path $Responses 'latest_call.json'
  Invoke-GetApi "$($env:BLAND_BASE_URL)/calls/$callId" $out
  Save-Archive $out
}

function Single-Cycle {
  if (Test-Path (Join-Path $Responses 'latest_call.json')) { Run-CodexPatch }
  Apply-Update
  Create-Version
  Publish-Version
  Link-Inbound
  Place-TestCall
  Start-Sleep -Seconds ([int]$env:SLEEP_SECONDS)
  Fetch-CallResult
}

if ($Mode -eq 'once') {
  Single-Cycle
  exit 0
}

for ($i = 1; $i -le [int]$env:MAX_ITERATIONS; $i++) {
  if (Test-Path (Join-Path $Root 'notes/STOP')) {
    Write-Host 'STOP file found. Exiting.'
    exit 0
  }
  Write-Host "=== Cycle $i/$($env:MAX_ITERATIONS) ==="
  Single-Cycle
}
