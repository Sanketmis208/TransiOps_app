import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:transi_ops_app/features/live_tracking/domain/location_sample.dart';

void main() {
  test('normalizes position ranges and converts m/s to km/h', () {
    final sample = LocationSample.fromPosition(
      id: 'stable-id',
      tripId: 'trip-1',
      batteryPct: 71,
      position: Position(
        longitude: 77.412615,
        latitude: 23.259933,
        timestamp: DateTime.utc(2026, 9, 1, 12),
        accuracy: 11.4,
        altitude: 523.2,
        altitudeAccuracy: 2,
        heading: 478,
        headingAccuracy: 2,
        speed: 10,
        speedAccuracy: 1,
        isMocked: true,
      ),
    );

    expect(sample.clientRequestId, 'stable-id');
    expect(sample.speedKph, 36);
    expect(sample.headingDeg, 118);
    expect(sample.isMocked, isTrue);
    expect(sample.toApiJson()['capturedAt'], '2026-09-01T12:00:00.000Z');
  });

  test('rejects invalid coordinates', () {
    expect(LocationSample.validCoordinates(91, 77), isFalse);
    expect(LocationSample.validCoordinates(23, -181), isFalse);
    expect(LocationSample.validCoordinates(23, 77), isTrue);
  });
}
