import '../../../core/api_client.dart';
import '../../live_tracking/domain/location_sample.dart';
import '../models/driver_trip.dart';

abstract interface class DriverTripGateway {
  Future<List<DriverTrip>> fetchAssignments();
  Future<DriverTrip> fetchAssignment(String tripId);
  Future<LocationUploadResult> uploadLocations(
    String tripId,
    List<LocationSample> points,
  );
}

class DriverTripRepository implements DriverTripGateway {
  const DriverTripRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<DriverTrip>> fetchAssignments() async {
    final response = await _api.get('/driver/me/trips') as List<dynamic>;
    return response
        .map((item) => DriverTrip.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<DriverTrip> fetchAssignment(String tripId) async =>
      DriverTrip.fromJson(
        await _api.get('/driver/me/trips/$tripId') as Map<String, dynamic>,
      );

  @override
  Future<LocationUploadResult> uploadLocations(
    String tripId,
    List<LocationSample> points,
  ) async => LocationUploadResult.fromJson(
    await _api.post('/driver/me/trips/$tripId/locations', {
          'points': points.map((point) => point.toApiJson()).toList(),
        })
        as Map<String, dynamic>,
  );
}
