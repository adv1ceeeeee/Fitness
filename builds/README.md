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

### Current local Android setup

On the Mac development machine, the Android SDK is installed at:

```bash
~/Library/Android/sdk
```

Release APKs are built with OpenJDK 17 and Flutter:

```bash
/usr/bin/env \
  JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  ANDROID_HOME=$HOME/Library/Android/sdk \
  ANDROID_SDK_ROOT=$HOME/Library/Android/sdk \
  PATH=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin:$HOME/Library/Android/sdk/platform-tools:$HOME/Library/Android/sdk/cmdline-tools/latest/bin:$PATH \
  /opt/homebrew/share/flutter/bin/flutter build apk \
    --release \
    --build-name 1.9.0 \
    --build-number 47 \
    --dart-define=DART_DEFINE_PRODUCTION=true \
    --no-tree-shake-icons
```

Then copy the artifact:

```bash
cp build/app/outputs/flutter-apk/app-release.apk \
  build/app/outputs/flutter-apk/sportwai-v1.9.0-47.apk
```

Verify package metadata and signing:

```bash
$HOME/Library/Android/sdk/build-tools/36.0.0/aapt dump badging \
  build/app/outputs/flutter-apk/app-release.apk

/usr/bin/env JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
  PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH \
  $HOME/Library/Android/sdk/build-tools/36.0.0/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

Current release signing certificate SHA-256:

```text
f993f0cc15e1be2b67c9559bd521dbf0a5f66ccd38896314509080421b5aaf23
```

As long as the package id, versionCode order, and signing certificate stay the
same, Android installs the new APK over the previous one and keeps app data.
