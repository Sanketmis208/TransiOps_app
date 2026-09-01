import 'package:flutter_test/flutter_test.dart';
import 'package:transi_ops_app/models/app_notification.dart';

void main() {
  test('parses notification routing data and unread state', () {
    final notification = AppNotification.fromJson({
      'id': 'notification-1',
      'type': 'TRIP_DISPATCHED',
      'title': 'Trip dispatched',
      'message': 'TRP0001 is ready.',
      'tripId': 'trip-1',
      'data': {'screen': 'trip', 'tripId': 'trip-1'},
      'readAt': null,
      'createdAt': '2026-09-01T12:00:00.000Z',
    });

    expect(notification.unread, isTrue);
    expect(notification.data['screen'], 'trip');
    expect(notification.tripId, 'trip-1');
  });
}
