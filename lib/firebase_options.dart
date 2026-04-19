// File generated manually for Firebase project: aksab-erp
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web has not been configured for this project yet.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD1eholuDAnsQTI-fcTqVVM4A9o7a02FUU',
    appId: '1:549455573441:android:1798013b9dc98ac6c4ff40',
    messagingSenderId: '549455573441',
    projectId: 'aksab-erp',
    databaseURL: 'https://aksab-erp-default-rtdb.firebaseio.com',
    storageBucket: 'aksab-erp.firebasestorage.app',
  );
}

