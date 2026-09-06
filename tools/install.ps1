# Install / uninstall the dsh-gpt-icon plugin into a local DSH Desktop harness.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1
#   powershell ... -File tools\install.ps1 -Uninstall
#   powershell ... -File tools\install.ps1 -HarnessDir "C:\path\to\harness"
#
# What install does:
#   1. copies the plugin payload to <harness>\local-plugins\dsh-gpt-icon
#   2. registers a file: dependency + bundle entry in
#      <harness>\profiles\web\package.json (idempotent, JSON-aware)
#   3. mirrors the plugin into <harness>\profiles\web\node_modules so it loads
#      on the next restart without waiting for pnpm
param(
  [string]$HarnessDir,
  [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'

$pluginName = 'dsh-gpt-icon'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

if (-not $HarnessDir) {
  $HarnessDir = $env:DSH_HOME
}
if (-not $HarnessDir) {
  $HarnessDir = Join-Path $env:APPDATA 'dsh-desktop\harness'
}
$HarnessDir = (Resolve-Path -LiteralPath $HarnessDir -ErrorAction Stop).Path
$profileDir = Join-Path $HarnessDir 'profiles\web'
$manifestPath = Join-Path $profileDir 'package.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "DSH profile manifest not found at $manifestPath (pass -HarnessDir or set DSH_HOME)."
}

if ($Uninstall) {
  if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.dependencies -and $manifest.dependencies.PSObject.Properties[$pluginName]) {
      $manifest.dependencies.PSObject.Properties.Remove($pluginName)
    }
    if ($manifest.dsh -and $manifest.dsh.profile -and $manifest.dsh.profile.bundles) {
      $manifest.dsh.profile.bundles = @($manifest.dsh.profile.bundles | Where-Object { $_ -ne $pluginName })
    }
    Write-Utf8NoBom $manifestPath ($manifest | ConvertTo-Json -Depth 100)
  }
  Remove-Item -LiteralPath (Join-Path $profileDir "node_modules\$pluginName") -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $HarnessDir "local-plugins\$pluginName") -Recurse -Force -ErrorAction SilentlyContinue
  try { schtasks /Delete /F /TN 'DSH GptIcon ExePatch' 2>&1 | Out-Null } catch { }
  Write-Host 'dsh-gpt-icon uninstalled.'
  Write-Host 'To restore the stock icons, copy the per-version backups back from'
  Write-Host "$HarnessDir\gpt-icon-data\backup\<version>\ (EXE: backup\exe\*.backup), then delete gpt-icon-data."
  return
}

$payload = @('package.json', 'cordis.patch.yml', 'lib', 'bin', 'assets', 'README.md')
foreach ($item in $payload) {
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $item))) {
    throw "Missing plugin payload: $item (run this script from a full checkout)."
  }
}

# 1. copy the payload into local-plugins
$dest = Join-Path $HarnessDir "local-plugins\$pluginName"
if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dest | Out-Null
foreach ($item in $payload) {
  Copy-Item -LiteralPath (Join-Path $repoRoot $item) -Destination $dest -Recurse -Force
}

# 2. register the bundle in the profile manifest
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if (-not ($manifest.dsh -and $manifest.dsh.profile)) {
  throw "$manifestPath does not look like a dsh profile manifest (missing dsh.profile)."
}
if (-not $manifest.dependencies) {
  $manifest | Add-Member -NotePropertyName dependencies -NotePropertyValue ([pscustomobject]@{})
}
$relative = 'file:../../local-plugins/' + $pluginName
if ($manifest.dependencies.PSObject.Properties[$pluginName]) {
  $manifest.dependencies.$pluginName = $relative
} else {
  $manifest.dependencies | Add-Member -NotePropertyName $pluginName -NotePropertyValue $relative
}
$bundles = [System.Collections.Generic.List[string]]@()
foreach ($b in @($manifest.dsh.profile.bundles)) { if ($b) { $bundles.Add([string]$b) } }
if (-not $bundles.Contains($pluginName)) { $bundles.Add($pluginName) }
$manifest.dsh.profile.bundles = $bundles
Write-Utf8NoBom $manifestPath ($manifest | ConvertTo-Json -Depth 100)

# 3. mirror into the profile's node_modules so the next restart picks it up
$modulesDir = Join-Path $profileDir 'node_modules'
if (-not (Test-Path -LiteralPath $modulesDir)) {
  throw "Profile node_modules not found at $modulesDir; start DSH once so it materializes, then re-run."
}
$mirror = Join-Path $modulesDir $pluginName
if (Test-Path -LiteralPath $mirror) { Remove-Item -LiteralPath $mirror -Recurse -Force }
Copy-Item -LiteralPath $dest -Destination $mirror -Recurse -Force

Write-Host "dsh-gpt-icon $((Get-Content -Raw (Join-Path $repoRoot 'package.json') | ConvertFrom-Json).version) installed."
Write-Host 'Fully quit DSH Desktop (tray -> Exit) and start it again to load the plugin.'
Write-Host "The EXE embedded icon is patched by a scheduled task after your first full quit."
