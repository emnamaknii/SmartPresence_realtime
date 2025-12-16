// File: lib/firebase_options.dart

// ignore_for_file: lines_longer_than_80_chars
import 'package:firebase_core/firebase_core.dart'
    show FirebaseOptions, FirebasePlatform;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // -------------------------------
  // ⭐ CONFIGURATION WEB (LA TIENTE)
  // -------------------------------
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyDGVNaBMJT7wGRsREEl4dAXSwMRcP1vkUc",
    authDomain: "miniprojet-38c25.firebaseapp.com",
    databaseURL:
    "https://miniprojet-38c25-default-rtdb.europe-west1.firebasedatabase.app",
    projectId: "miniprojet-38c25",
    storageBucket: "miniprojet-38c25.firebasestorage.app",
    messagingSenderId: "1094556437706",
    appId: "1:1094556437706:web:91703ae1bc186d99cfb833",
    measurementId: "G-ZTH3ZSF8PR",
  );

  // -------------------------------
  // ⭐ CONFIG ANDROID (NE PAS MODIFIER)
  // -------------------------------
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDGVNaBMJT7wGRsREEl4dAXSwMRcP1vkUc',
    appId: '1:1094556437706:android:06a48c7b197ed414cfb833',
    messagingSenderId: '1094556437706',
    projectId: 'miniprojet-38c25',
    databaseURL:
    "https://miniprojet-38c25-default-rtdb.europe-west1.firebasedatabase.app",
    storageBucket: "miniprojet-38c25.firebasestorage.app",
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_KEY',
    appId: 'YOUR_IOS_APPID',
    messagingSenderId: '1094556437706',
    projectId: 'miniprojet-38c25',
    databaseURL:
    "https://miniprojet-38c25-default-rtdb.europe-west1.firebasedatabase.app",
    storageBucket: "miniprojet-38c25.firebasestorage.app",
  );

  static const FirebaseOptions macos = ios;
  static const FirebaseOptions windows = android;
  static const FirebaseOptions linux = android;
}
