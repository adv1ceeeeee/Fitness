# Builds

Release artifacts for Sportify, organised by platform.

```
builds/
  android/
    apk/    Release-signed APKs (sportify-v{version}.apk)
    aab/    Android App Bundles for Google Play
  ios/
    ipa/    iOS App Store archives
```

Binaries are **not** committed to git (see `.gitignore`). Each folder keeps a
`.gitkeep` so the directory structure exists for fresh clones.

## Android — build a signed APK

```powershell
./scripts/build_android.ps1
```

Produces `builds/android/apk/sportify-v{version}+{build}.apk`.

Requirements: `android/key.properties` + `android/app/sportify-release.jks`
must exist locally (neither is in git).
