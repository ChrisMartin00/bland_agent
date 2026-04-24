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
    if ($_ -match '^\s*#') { return }
    if ($_ -match '^(\w+)=(.*)$') {
      [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
  }
}

if (-not $env:BLAND_BASE_URL) { $env:BLAND_BASE_URL = 'https://api.bland.ai/v1' }
if (-not $env:MAX_ITERATIONS) { $env:MAX_ITERATIONS = '10' }
if (-not $env:SLEEP_SECONDS) { $env:SLEEP_SECONDS = '8' }
if (-not $env:CODEX_CMD) { $env:CODEX_CMD = 'codex' }
if (-not $env:INBOUND_UPDATE_METHOD) { $env:INBOUND_UPDATE_METHOD = 'POST' }
if (-not $env:REQUIRED_CRITICAL_VARS) { $env:REQUIRED_CRITICAL_VARS = 'partner_id,product_id,qty,quote_id' }

function Require-Env([string[]]$Names) {
  foreach ($name in $Names) {
    if (-not (Get-Item "Env:$name" -ErrorAction SilentlyContinue)) {
      throw "Missing required environment variable: $name"
    }
    $value = (Get-Item "Env:$name").Value
    if ([string]::IsNullOrWhiteSpace($value)) {
      throw "Environment variable is empty: $name"
    }
  }
}

function Save-Archive([string]$Path) {
  if (-not (Test-Path $Path)) { return }
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  Copy-Item $Path (Join-Path $Archive ("${stamp}_" + [IO.Path]::GetFileName($Path))) -Force
}

function Read-JsonFile([string]$Path) {
  if (-not (Test-Path $Path)) { throw "Missing file: $Path" }
  $raw = Get-Content $Path -Raw
  if ([string]::IsNullOrWhiteSpace($raw)) { throw "Empty JSON file: $Path" }
  return $raw | ConvertFrom-Json
}

function Write-JsonFile([string]$Path, $Object) {
  $Object | ConvertTo-Json -Depth 100 | Set-Content -Encoding UTF8 $Path
}

function Invoke-JsonApi([string]$Method, [string]$Url, [string]$BodyPath, [string]$OutPath) {
  if (-not (Test-Path $BodyPath)) { throw "Missing request body: $BodyPath" }

  $headers = @(
    "authorization: $($env:BLAND_API_KEY)",
    'Content-Type: application/json'
  )

  $args = @('-sS', '-X', $Method)
  foreach ($h in $headers) { $args += @('-H', $h) }
  $args += @($Url, '--data', "@$BodyPath")

  & curl @args | Set-Content -Encoding UTF8 $OutPath
  Save-Archive $OutPath
}

function Invoke-GetApi([string]$Url, [string]$OutPath) {
  $headers = @(
    "authorization: $($env:BLAND_API_KEY)",
    'Content-Type: application/json'
  )

  $args = @('-sS')
  foreach ($h in $headers) { $args += @('-H', $h) }
  $args += $Url

  & curl @args | Set-Content -Encoding UTF8 $OutPath
  Save-Archive $OutPath
}

function Assert-JsonFileOk([string]$Path, [string]$Operation) {
  $json = Read-JsonFile $Path

  if ($json.status -eq 'error') {
    throw "$Operation failed: $($json.message)"
  }

  if ($json.errors -and $json.errors.Count -gt 0) {
    $msg = ($json.errors | ForEach-Object {
      if ($_.message) { $_.message } elseif ($_ -is [string]) { $_ } else { $_ | ConvertTo-Json -Compress }
    }) -join ' | '
    throw "$Operation failed: $msg"
  }

  if ($json.message -and $json.message -match 'error') {
    throw "$Operation failed: $($json.message)"
  }

  return $json
}

function Run-CodexPatch {
  $promptPath = Join-Path $Root 'prompts/codex_task.txt'
  if (-not (Test-Path $promptPath)) { throw "Missing Codex prompt file: $promptPath" }

  Push-Location $Root
  try {
    $prompt = Get-Content $promptPath -Raw
    & $env:CODEX_CMD -C . $prompt
    if ($LASTEXITCODE -ne 0) {
      throw "Codex command failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
}

function Apply-Update {
  $out = Join-Path $Responses 'update_pathway_response.json'
  $body = Join-Path $Root 'requests/bland/update_pathway.json'
  Invoke-JsonApi 'POST' "$($env:BLAND_BASE_URL)/pathway/$($env:PATHWAY_ID)" $body $out
  $json = Assert-JsonFileOk $out 'Pathway update'
  return $json
}

function Create-Version {
  $out = Join-Path $Responses 'create_version_response.json'
  $body = Join-Path $Root 'requests/bland/create_version.json'
  Invoke-JsonApi 'POST' "$($env:BLAND_BASE_URL)/pathway/$($env:PATHWAY_ID)/version" $body $out
  $json = Assert-JsonFileOk $out 'Create version'

  $version = $null
  if ($json.data.version_number) { $version = $json.data.version_number }
  elseif ($json.version_number) { $version = $json.version_number }
  elseif ($json.data.new_version_number) { $version = $json.data.new_version_number }

  if (-not $version) {
    throw 'Could not parse version number from create version response.'
  }

  $pubPath = Join-Path $Root 'requests/bland/publish_version.json'
  $pub = Read-JsonFile $pubPath
  $pub.version_id = [int]$version
  Write-JsonFile $pubPath $pub

  Set-Content -Encoding UTF8 (Join-Path $Responses 'latest_version_number.txt') $version
  return [int]$version
}

function Publish-Version {
  $out = Join-Path $Responses 'publish_response.json'
  $body = Join-Path $Root 'requests/bland/publish_version.json'
  Invoke-JsonApi 'POST' "$($env:BLAND_BASE_URL)/pathway/$($env:PATHWAY_ID)/publish" $body $out
  $json = Assert-JsonFileOk $out 'Publish version'

  $publishedVersion = $null
  if ($json.data.new_version_number) { $publishedVersion = $json.data.new_version_number }
  elseif ($json.new_version_number) { $publishedVersion = $json.new_version_number }

  if ($publishedVersion) {
    Set-Content -Encoding UTF8 (Join-Path $Responses 'latest_published_version.txt') $publishedVersion
  }

  return $json
}

function Link-Inbound {
  if ([string]::IsNullOrWhiteSpace($env:INBOUND_NUMBER)) { return $null }

  $path = Join-Path $Root 'requests/bland/link_inbound_number.json'
  $json = Read-JsonFile $path
  $json.pathway_id = $env:PATHWAY_ID

  $versionPath = Join-Path $Responses 'latest_version_number.txt'
  if (Test-Path $versionPath) {
    $version = (Get-Content $versionPath -Raw).Trim()
    if ($version) { $json.pathway_version = [int]$version }
  }

  Write-JsonFile $path $json

  $out = Join-Path $Responses 'link_inbound_response.json'
  Invoke-JsonApi $env:INBOUND_UPDATE_METHOD "$($env:BLAND_BASE_URL)/inbound/$($env:INBOUND_NUMBER)" $path $out
  $linked = Assert-JsonFileOk $out 'Link inbound number'
  return $linked
}

function Place-TestCall {
  $path = Join-Path $Root 'requests/tests/test_call.json'
  $json = Read-JsonFile $path

  $json.phone_number = $env:TEST_PHONE_NUMBER
  $json.pathway_id = $env:PATHWAY_ID

  $versionPath = Join-Path $Responses 'latest_version_number.txt'
  if (Test-Path $versionPath) {
    $version = (Get-Content $versionPath -Raw).Trim()
    if ($version) { $json.pathway_version = [int]$version }
  }

  Write-JsonFile $path $json

  $out = Join-Path $Responses 'test_call_create.json'
  Invoke-JsonApi 'POST' "$($env:BLAND_BASE_URL)/calls" $path $out
  $resp = Assert-JsonFileOk $out 'Create test call'

  $callId = $resp.call_id
  if (-not $callId -and $resp.data.call_id) { $callId = $resp.data.call_id }
  if (-not $callId) { throw 'Could not parse call_id.' }

  Set-Content -Encoding UTF8 (Join-Path $Responses 'latest_call_id.txt') $callId
  return $callId
}

function Fetch-CallResult {
  $callIdPath = Join-Path $Responses 'latest_call_id.txt'
  if (-not (Test-Path $callIdPath)) { throw 'Missing latest_call_id.txt' }

  $callId = (Get-Content $callIdPath -Raw).Trim()
  if (-not $callId) { throw 'latest_call_id.txt is empty' }

  $out = Join-Path $Responses 'latest_call.json'
  Invoke-GetApi "$($env:BLAND_BASE_URL)/calls/$callId" $out
  $json = Read-JsonFile $out

  if ($json.error_message) {
    throw "Fetched call contains error_message: $($json.error_message)"
  }

  return $json
}

function Test-CriticalVarsPresent($CallJson) {
  $required = $env:REQUIRED_CRITICAL_VARS.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  $missing = @()

  foreach ($name in $required) {
    $value = $null
    if ($CallJson.variables -and $null -ne $CallJson.variables.$name) {
      $value = $CallJson.variables.$name
    }

    $isMissing = $false
    if ($null -eq $value) { $isMissing = $true }
    elseif ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { $isMissing = $true }

    if ($isMissing) { $missing += $name }
  }

  return $missing
}

function Test-CallPassed($CallJson) {
  if (-not $CallJson) { return $false }

  if ($CallJson.pathway_id -and $env:PATHWAY_ID -and $CallJson.pathway_id -ne $env:PATHWAY_ID) {
    throw "Call used wrong pathway_id. Expected $($env:PATHWAY_ID), got $($CallJson.pathway_id)"
  }

  if ($CallJson.status -and $CallJson.status -notin @('completed', 'queued', 'in-progress')) {
    throw "Unexpected call status: $($CallJson.status)"
  }

  $missing = Test-CriticalVarsPresent $CallJson
  Set-Content -Encoding UTF8 (Join-Path $Responses 'latest_missing_vars.txt') ($missing -join ',')

  if ($missing.Count -gt 0) {
    Write-Host "Critical vars missing: $($missing -join ', ')"
    return $false
  }

  return $true
}

function Write-CycleSummary($CallJson, [bool]$Passed) {
  $summaryPath = Join-Path $Responses 'latest_cycle_summary.txt'
  $lines = @()
  $lines += "timestamp=$(Get-Date -Format s)"
  $lines += "passed=$Passed"
  if ($CallJson.call_id) { $lines += "call_id=$($CallJson.call_id)" }
  if ($CallJson.pathway_id) { $lines += "pathway_id=$($CallJson.pathway_id)" }
  if ($CallJson.pathway_version) { $lines += "pathway_version=$($CallJson.pathway_version)" }
  if ($CallJson.status) { $lines += "status=$($CallJson.status)" }
  Set-Content -Encoding UTF8 $summaryPath $lines
  Save-Archive $summaryPath
}

function Single-Cycle {
  if (Test-Path (Join-Path $Responses 'latest_call.json')) {
    Write-Host 'Running Codex patch based on latest_call.json...'
    Run-CodexPatch
  }

  Write-Host 'Applying pathway update...'
  Apply-Update | Out-Null

  Write-Host 'Creating version...'
  $version = Create-Version
  Write-Host "Created version: $version"

  Write-Host 'Publishing version...'
  Publish-Version | Out-Null

  Write-Host 'Linking inbound number...'
  Link-Inbound | Out-Null

  Write-Host 'Placing test call...'
  $callId = Place-TestCall
  Write-Host "Created call: $callId"

  Start-Sleep -Seconds ([int]$env:SLEEP_SECONDS)

  Write-Host 'Fetching call result...'
  $call = Fetch-CallResult

  $passed = Test-CallPassed $call
  Write-CycleSummary $call $passed

  if (-not $passed) {
    throw 'Cycle failed critical validation. See responses/latest_call.json and responses/latest_missing_vars.txt'
  }

  Write-Host 'Cycle passed critical validation.'
}

Require-Env @('BLAND_API_KEY', 'PATHWAY_ID', 'TEST_PHONE_NUMBER')

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

  try {
    Single-Cycle
    Write-Host 'Cycle passed. Exiting loop mode early.'
    exit 0
  } catch {
    Write-Host "Cycle failed: $($_.Exception.Message)"
    if ($i -eq [int]$env:MAX_ITERATIONS) { throw }
    Start-Sleep -Seconds ([int]$env:SLEEP_SECONDS)
  }
}
