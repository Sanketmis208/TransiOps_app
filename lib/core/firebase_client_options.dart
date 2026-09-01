import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

abstract final class FirebaseClientOptions {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'in.transitops.transiOpsApp',
  );

  static bool get configured =>
      apiKey.isNotEmpty &&
      projectId.isNotEmpty &&
      senderId.isNotEmpty &&
      (Platform.isIOS ? iosAppId.isNotEmpty : androidAppId.isNotEmpty);

  static FirebaseOptions get current => FirebaseOptions(
    apiKey: apiKey,
    appId: Platform.isIOS ? iosAppId : androidAppId,
    messagingSenderId: senderId,
    projectId: projectId,
    iosBundleId: Platform.isIOS ? iosBundleId : null,
  );
}
