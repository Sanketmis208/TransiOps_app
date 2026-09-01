import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/session_controller.dart';
import 'core/push_notification_controller.dart';
import 'core/auth/driver_session_store.dart';
import 'features/driver_trips/data/driver_trip_repository.dart';
import 'features/live_tracking/controllers/trip_tracking_controller.dart';
import 'features/live_tracking/data/location_queue.dart';
import 'features/live_tracking/services/trip_location_service.dart';
import 'screens/app_shell.dart';
import 'screens/change_password_screen.dart';
import 'screens/driver_onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'models/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  final api = ApiClient();
  final session = SessionController(
    api,
    tokenStore: SecureDriverSessionStore(),
  );
  final tracking = TripTrackingController(
    repository: DriverTripRepository(api),
    queue: SqlCipherLocationQueue(),
    locationService: GeolocatorTripLocationService(),
    session: session,
  );
  final navigatorKey = GlobalKey<NavigatorState>();
  final push = PushNotificationController(
    api: api,
    session: session,
    navigatorKey: navigatorKey,
  );
  runApp(
    TransitOpsApp(
      api: api,
      session: session,
      tracking: tracking,
      push: push,
      navigatorKey: navigatorKey,
    ),
  );
  unawaited(push.initialize());
  unawaited(_restore(session, tracking));
}

Future<void> _restore(
  SessionController session,
  TripTrackingController tracking,
) async {
  await session.restore();
  await tracking.initialize();
}

class TransitOpsApp extends StatelessWidget {
  const TransitOpsApp({
    super.key,
    required this.api,
    required this.session,
    required this.tracking,
    required this.push,
    required this.navigatorKey,
  });

  final ApiClient api;
  final SessionController session;
  final TripTrackingController tracking;
  final PushNotificationController push;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: api),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: tracking),
        ChangeNotifierProvider.value(value: push),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'TransitOps',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (_, child) => AppBackdrop(child: child ?? const SizedBox()),
        home: Consumer<SessionController>(
          builder: (_, state, _) {
            if (state.restoring) return const SplashScreen();
            final user = state.user;
            if (user == null) return const LoginScreen();
            if (user.mustChangePassword) return const ChangePasswordScreen();
            if (user.role == UserRole.driver) {
              return const DriverOnboardingScreen();
            }
            return const AppShell();
          },
        ),
      ),
    );
  }
}
