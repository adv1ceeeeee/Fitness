# Build a release-signed Android APK and copy it into builds/android/apk/.
# Usage (from project root):
#   ./scripts/build_android.ps1
#
# The Flutter/Dart AOT toolchain mangles non-ASCII paths on Windows, so if the
# project sits under a Cyrillic path we transparently build via a subst'd
# drive letter (P: by default) which gives the toolchain an ASCII path.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot
$realRoot = (Get-Location).Path

# Sanity: keystore must be present.
if (-not (Test-Path "android/key.properties")) {
    Write-Host "ERROR: android/key.properties not found. Copy from key.properties.example and fill in passwords." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path "android/app/sportify-release.jks")) {
    Write-Host "ERROR: android/app/sportify-release.jks not found." -ForegroundColor Red
    exit 1
}

# If the path contains non-ASCII characters, route the build through a subst drive.
$nonAscii = [regex]::IsMatch($realRoot, '[^\u0000-\u007F]')
$buildRoot = $realRoot
$substDrive = $null
if ($nonAscii) {
    $substDrive = "P:"
    $existing = subst | Select-String -Pattern "^${substDrive}\\"
    if ($existing) {
        Write-Host "Using existing $substDrive subst mapping" -ForegroundColor DarkGray
    } else {
        Write-Host "Creating subst $substDrive -> $realRoot" -ForegroundColor DarkGray
        subst $substDrive $realRoot
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: subst failed." -ForegroundColor Red
            exit 1
        }
    }
    $buildRoot = "${substDrive}\"
}

Set-Location $buildRoot
Write-Host "Build root: $buildRoot" -ForegroundColor Cyan

# Extract version from pubspec.yaml.
$versionLine = (Get-Content pubspec.yaml | Select-String -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
Write-Host "Version: $versionLine" -ForegroundColor Cyan

Write-Host "Running flutter build apk --release..." -ForegroundColor Cyan
flutter build apk --release --no-tree-shake-icons
if ($LASTEXITCODE -ne 0) {
    Write-Host "flutter build failed." -ForegroundColor Red
    exit 1
}

$sourceApk = Join-Path $buildRoot "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $sourceApk)) {
    Write-Host "ERROR: expected APK not found at $sourceApk" -ForegroundColor Red
    exit 1
}

$outName = "sportify-v$versionLine.apk"
$outDir = Join-Path $buildRoot "builds\android\apk"
$outPath = Join-Path $outDir $outName

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item -Force $sourceApk $outPath

$sizeMb = [math]::Round((Get-Item $outPath).Length / 1MB, 2)
Write-Host ""
Write-Host "OK  $outPath  ($sizeMb MB)" -ForegroundColor Green
if ($substDrive) {
    Write-Host "    (also visible at $realRoot\builds\android\apk\$outName)" -ForegroundColor DarkGray
}
