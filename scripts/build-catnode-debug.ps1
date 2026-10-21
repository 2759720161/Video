param(
    [ValidateSet('default', 'ohosTest')][string]$Target = 'default',
    [string]$StudioRoot = 'D:\HarmonyOS\API26\DevEco Studio'
)
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$projectRoot = Split-Path -Parent $PSScriptRoot
$profilePath = Join-Path $projectRoot 'build-profile.json5'
$localPath = Join-Path $projectRoot 'build-profile.local.json5'
$backupPath = Join-Path $projectRoot 'native\node\dist\signing-profile-backup.json5'
if (Test-Path -LiteralPath $backupPath) {
    throw 'A previous signing backup exists. Restore or review it before building again.'
}
$originalBytes = [System.IO.File]::ReadAllBytes($profilePath)
$originalHash = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
$profile = Get-Content -LiteralPath $profilePath -Encoding UTF8 -Raw | ConvertFrom-Json
$localProfile = Get-Content -LiteralPath $localPath -Encoding UTF8 -Raw | ConvertFrom-Json
if (!$localProfile.app.signingConfigs) { throw 'Local debug signing configuration is missing.' }
$profile.app.signingConfigs = $localProfile.app.signingConfigs
New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
[System.IO.File]::WriteAllBytes($backupPath, $originalBytes)
$workingHash = ''
try {
    $temporaryProfile = $profile | ConvertTo-Json -Depth 40
    [System.IO.File]::WriteAllText($profilePath, $temporaryProfile, [System.Text.UTF8Encoding]::new($false))
    $workingHash = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
    $env:DEVECO_SDK_HOME = Join-Path $StudioRoot 'sdk'
    $env:JAVA_HOME = Join-Path $StudioRoot 'jbr'
    & (Join-Path $StudioRoot 'tools\node\node.exe') (Join-Path $StudioRoot 'tools\hvigor\bin\hvigorw.js') `
        --mode module -p product=default -p "module=entry@$Target" -p buildMode=debug assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw 'Debug HAP build failed.' }
    $outputDir = Join-Path $projectRoot "entry\build\default\outputs\$Target"
    Copy-Item -LiteralPath (Join-Path $outputDir "entry-$Target-signed.hap") `
        -Destination (Join-Path $outputDir "entry-$Target-debug-signed.hap") -Force
} finally {
    $currentHash = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
    if ($workingHash -and $currentHash -ne $workingHash) {
        throw "The build profile was edited during signing. Original bytes remain at $backupPath."
    }
    [System.IO.File]::WriteAllBytes($profilePath, $originalBytes)
    if ((Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash -ne $originalHash) {
        throw "Build profile restoration failed. Backup remains at $backupPath."
    }
    Remove-Item -LiteralPath $backupPath
    Write-Output 'Original build profile restored byte for byte.'
}
