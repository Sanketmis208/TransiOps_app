import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

class LocationSample {
  const LocationSample({
    required this.clientRequestId,
    required this.tripId,
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.capturedAt,
    this.speedKph,
    this.headingDeg,
    this.altitudeM,
    this.batteryPct,
    this.isMocked,
  });

  final String clientRequestId;
  final String tripId;
  final double latitude;
  final double longitude;
  final double accuracyM;
  final double? speedKph;
  final double? headingDeg;
  final double? altitudeM;
  final int? batteryPct;
  final bool? isMocked;
  final DateTime capturedAt;

  static LocationSample fromPosition({
    required String id,
    required String tripId,
    required Position position,
    int? batteryPct,
  }) {
    if (!validCoordinates(position.latitude, position.longitude)) {
      throw const FormatException('Invalid GPS coordinates');
    }
    return LocationSample(
      clientRequestId: id,
      tripId: tripId,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: math.max(0, position.accuracy),
      speedKph: position.speed >= 0
          ? metresPerSecondToKph(position.speed)
          : null,
      headingDeg: position.heading >= 0
          ? normalizeHeading(position.heading)
          : null,
      altitudeM: position.altitude.isFinite ? position.altitude : null,
      batteryPct: batteryPct?.clamp(0, 100),
      isMocked: position.isMocked,
      capturedAt: position.timestamp.toUtc(),
    );
  }

  static bool validCoordinates(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  static double metresPerSecondToKph(double speed) => speed * 3.6;

  static double normalizeHeading(double heading) =>
      ((heading % 360) + 360) % 360;

  Map<String, dynamic> toApiJson() => {
    'clientRequestId': clientRequestId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracyM': accuracyM,
    if (speedKph != null) 'speedKph': speedKph,
    if (headingDeg != null) 'headingDeg': headingDeg,
    if (altitudeM != null) 'altitudeM': altitudeM,
    if (batteryPct != null) 'batteryPct': batteryPct,
    if (isMocked != null) 'isMocked': isMocked,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toDatabaseMap({bool quarantined = false}) => {
    'client_request_id': clientRequestId,
    'trip_id': tripId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_m': accuracyM,
    'speed_kph': speedKph,
    'heading_deg': headingDeg,
    'altitude_m': altitudeM,
    'battery_pct': batteryPct,
    'is_mocked': isMocked == null ? null : (isMocked! ? 1 : 0),
    'captured_at': capturedAt.toUtc().millisecondsSinceEpoch,
    'quarantined': quarantined ? 1 : 0,
  };

  factory LocationSample.fromDatabaseMap(Map<String, dynamic> row) =>
      LocationSample(
        clientRequestId: row['client_request_id'] as String,
        tripId: row['trip_id'] as String,
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        accuracyM: (row['accuracy_m'] as num).toDouble(),
        speedKph: (row['speed_kph'] as num?)?.toDouble(),
        headingDeg: (row['heading_deg'] as num?)?.toDouble(),
        altitudeM: (row['altitude_m'] as num?)?.toDouble(),
        batteryPct: (row['battery_pct'] as num?)?.toInt(),
        isMocked: row['is_mocked'] == null
            ? null
            : (row['is_mocked'] as num).toInt() == 1,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['captured_at'] as num).toInt(),
          isUtc: true,
        ),
      );
}
