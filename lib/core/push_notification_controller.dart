import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification.dart';
import '../screens/notification_center_screen.dart';
import 'api_client.dart';
import 'firebase_client_options.dart';
import 'session_controller.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!FirebaseClientOptions.configured) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: FirebaseClientOptions.current);
  }
}

class PushNotificationController extends ChangeNotifier {
  PushNotificationController({
    required ApiClient api,
    required SessionController session,
    required this.navigatorKey,
  }) : _api = api,
       _session = session;

  final ApiClient _api;
  final SessionController _session;
  final GlobalKey<NavigatorState> navigatorKey;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  List<AppNotification> items = const [];
  int unreadCount = 0;
  bool loading = false;
  bool available = false;
  String? error;
  String? _deviceToken;
  String? _registeredUserId;
  Map<String, dynamic>? _pendingTap;
  bool _syncing = false;

  Future<void> initialize() async {
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          _openPayload(jsonDecode(response.payload!) as Map<String, dynamic>);
        }
      },
    );
    _session.beforeLogout = unregisterCurrentDevice;
    _session.addListener(_sessionChanged);

    if (!FirebaseClientOptions.configured) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: FirebaseClientOptions.current);
      }
      final messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      _subscriptions.add(
        FirebaseMessaging.onMessage.listen(_showForegroundMessage),
      );
      _subscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          (message) => _openPayload(message.data),
        ),
      );
      _subscriptions.add(
        messaging.onTokenRefresh.listen((token) async {
          _deviceToken = token;
          await _registerToken();
        }),
      );
      available = true;
      notifyListeners();
      await _syncForSession();
      final initial = await messaging.getInitialMessage();
      if (initial != null) _openPayload(initial.data);
    } catch (exception) {
      error = 'Push notifications could not start: $exception';
      notifyListeners();
    }
  }

  void _sessionChanged() {
    unawaited(_syncForSession());
  }

  Future<void> _syncForSession() async {
    if (_syncing || !available || _session.restoring) return;
    final user = _session.user;
    if (user == null) return;
    _syncing = true;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      _deviceToken ??= await FirebaseMessaging.instance.getToken();
      await _registerToken();
      await refresh();
      if (_pendingTap != null) {
        final payload = _pendingTap!;
        _pendingTap = null;
        _openPayload(payload);
      }
    } catch (exception) {
      error = 'Notifications are unavailable on this device: $exception';
      notifyListeners();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _registerToken() async {
    final token = _deviceToken;
    final user = _session.user;
    if (token == null || user == null || _api.token == null) return;
    await _api.post('/push/devices', {
      'token': token,
      'platform': Platform.isIOS ? 'IOS' : 'ANDROID',
    });
    _registeredUserId = user.id;
  }

  Future<void> unregisterCurrentDevice() async {
    final token = _deviceToken;
    if (token == null || _registeredUserId == null || _api.token == null) {
      return;
    }
    try {
      await _api.post('/push/devices/unregister', {'token': token});
    } catch (_) {
      // A new login reassigns this unique token, so logout must still proceed.
    } finally {
      _registeredUserId = null;
      items = const [];
      unreadCount = 0;
      notifyListeners();
    }
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification != null) {
      await _local.show(
        id:
            message.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff),
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'transitops_operations',
            'TransitOps operations',
            channelDescription: 'Trips, drivers, expenses and maintenance',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_session.user == null || _api.token == null || loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final response =
          await _api.get('/notifications?limit=50') as Map<String, dynamic>;
      items = (response['items'] as List<dynamic>? ?? [])
          .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
          .toList();
      unreadCount = (response['unreadCount'] as num?)?.toInt() ?? 0;
    } catch (exception) {
      error = exception.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(AppNotification notification) async {
    if (!notification.unread) return;
    await _api.post('/notifications/${notification.id}/read');
    await refresh();
  }

  Future<void> markAllRead() async {
    await _api.post('/notifications/read-all');
    await refresh();
  }

  void openInbox() {
    if (_session.user == null) return;
    unawaited(refresh());
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => const NotificationCenterScreen()),
    );
  }

  void _openPayload(Map<String, dynamic> payload) {
    if (_session.user == null || navigatorKey.currentState == null) {
      _pendingTap = payload;
      return;
    }
    openInbox();
  }

  @override
  void dispose() {
    _session.beforeLogout = null;
    _session.removeListener(_sessionChanged);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
