// GENERATED FILE — replace with output of `flutterfire configure`
//
// Steps:
//   1. Create a Firebase project at https://console.firebase.google.com
//   2. Install FlutterFire CLI:  dart pub global activate flutterfire_cli
//   3. Run from project root:    flutterfire configure
//      - Select your Firebase project
//      - Select platforms: android, ios
//   4. Commit the generated firebase_options.dart, google-services.json,
//      and GoogleService-Info.plist
//
// Until this is done the app compiles fine but FCM tokens will not be
// registered (DeviceTokenService.register is a no-op without a real token).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions not configured for ${defaultTargetPlatform.name}. '
          'Run `flutterfire configure` to generate this file.',
        );
    }
  }

  // ── Replace these placeholders with values from flutterfire configure ──────

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'REPLACE_ME',
    storageBucket: 'REPLACE_ME',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'REPLACE_ME',
    storageBucket: 'REPLACE_ME',
    iosBundleId: 'REPLACE_ME',
  );
}
