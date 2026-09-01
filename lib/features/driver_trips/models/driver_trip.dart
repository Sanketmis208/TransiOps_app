import '../../../models/models.dart';

class DriverTrip {
  const DriverTrip({required this.trip, this.tracking});

  final Trip trip;
  final ServerTrackingSnapshot? tracking;

  String get id => trip.id;
  String get status => trip.status;
  bool get isTrackable => status == 'DISPATCHED' || status == 'IN_PROGRESS';
  bool get isTerminal => status == 'COMPLETED' || status == 'CANCELLED';

  factory DriverTrip.fromJson(Map<String, dynamic> json) => DriverTrip(
    trip: Trip.fromJson(json),
    tracking: json['tracking'] is Map<String, dynamic>
        ? ServerTrackingSnapshot.fromJson(
            json['tracking'] as Map<String, dynamic>,
          )
        : null,
  );

  DriverTrip withStatus(String status) => DriverTrip(
    trip: trip.copyWith(status: status),
    tracking: tracking,
  );
}

class ServerTrackingSnapshot {
  const ServerTrackingSnapshot({required this.status, this.latestLocation});

  final String status;
  final ServerLocation? latestLocation;

  factory ServerTrackingSnapshot.fromJson(Map<String, dynamic> json) =>
      ServerTrackingSnapshot(
        status: json['status']?.toString() ?? 'WAITING_FOR_GPS',
        latestLocation: json['latestLocation'] is Map<String, dynamic>
            ? ServerLocation.fromJson(
                json['latestLocation'] as Map<String, dynamic>,
              )
            : null,
      );
}

class ServerLocation {
  const ServerLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyM;
  final DateTime capturedAt;

  factory ServerLocation.fromJson(Map<String, dynamic> json) => ServerLocation(
    latitude: number(json['latitude']),
    longitude: number(json['longitude']),
    accuracyM: number(json['accuracyM']),
    capturedAt: DateTime.parse(json['capturedAt'] as String).toUtc(),
  );
}

class LocationUploadResult {
  const LocationUploadResult({
    required this.accepted,
    required this.duplicates,
    required this.tripStatus,
    this.acknowledgedAt,
  });

  final int accepted;
  final int duplicates;
  final String tripStatus;
  final DateTime? acknowledgedAt;

  factory LocationUploadResult.fromJson(Map<String, dynamic> json) {
    final latest = json['latestLocation'];
    return LocationUploadResult(
      accepted: (json['accepted'] as num?)?.toInt() ?? 0,
      duplicates: (json['duplicates'] as num?)?.toInt() ?? 0,
      tripStatus: json['tripStatus']?.toString() ?? 'IN_PROGRESS',
      acknowledgedAt:
          latest is Map<String, dynamic> && latest['receivedAt'] != null
          ? DateTime.parse(latest['receivedAt'] as String).toUtc()
          : null,
    );
  }
}
