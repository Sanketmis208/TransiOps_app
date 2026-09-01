import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transi_ops_app/core/api_client.dart';
import 'package:transi_ops_app/core/auth/driver_session_store.dart';
import 'package:transi_ops_app/core/session_controller.dart';
import 'package:transi_ops_app/features/driver_trips/data/driver_trip_repository.dart';
import 'package:transi_ops_app/features/driver_trips/models/driver_trip.dart';
import 'package:transi_ops_app/features/live_tracking/controllers/trip_tracking_controller.dart';
import 'package:transi_ops_app/features/live_tracking/data/location_queue.dart';
import 'package:transi_ops_app/features/live_tracking/domain/location_sample.dart';
import 'package:transi_ops_app/features/live_tracking/services/trip_location_service.dart';
import 'package:transi_ops_app/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'first accepted point updates status and double start uses one stream',
    () async {
      final session = await signedInSession();
      final repository = FakeTripRepository();
      final queue = MemoryLocationQueue();
      final location = FakeLocationService();
      final controller = TripTrackingController(
        repository: repository,
        queue: queue,
        locationService: location,
        session: session,
      );

      await controller.startTracking(repository.trip);
      await controller.startTracking(repository.trip);

      expect(controller.activeTrip?.status, 'IN_PROGRESS');
      expect(controller.state, TripTrackingState.activeOnline);
      expect(controller.latitude, 23.259933);
      expect(controller.longitude, 77.412615);
      expect(location.streamStarts, 1);
      expect(repository.uploadedIds, hasLength(1));
      expect(await queue.count(repository.trip.id), 0);
      controller.dispose();
      await location.close();
    },
  );

  test('permission denial keeps the assignment available', () async {
    final session = await signedInSession();
    final repository = FakeTripRepository();
    final location = FakeLocationService(
      permission: TrackingPermissionState.denied,
    );
    final controller = TripTrackingController(
      repository: repository,
      queue: MemoryLocationQueue(),
      locationService: location,
      session: session,
    );

    await controller.startTracking(repository.trip);

    expect(controller.state, TripTrackingState.permissionRequired);
    expect(controller.activeTrip?.id, repository.trip.id);
    expect(location.streamStarts, 0);
    controller.dispose();
    await location.close();
  });

  test('network recovery uploads the same stable ID oldest first', () async {
    final session = await signedInSession();
    final repository = FakeTripRepository()
      ..uploadError = const ApiException('offline');
    final queue = MemoryLocationQueue();
    final location = FakeLocationService();
    final controller = TripTrackingController(
      repository: repository,
      queue: queue,
      locationService: location,
      session: session,
    );

    await controller.startTracking(repository.trip);
    final queued = await queue.oldestBatch(repository.trip.id);
    final originalId = queued.single.clientRequestId;
    expect(controller.state, TripTrackingState.activeOffline);

    repository.uploadError = null;
    await controller.flush();

    expect(repository.uploadedIds.last, originalId);
    expect(await queue.count(repository.trip.id), 0);
    controller.dispose();
    await location.close();
  });

  test('401 retains encrypted queue and requires a new login', () async {
    final session = await signedInSession();
    final repository = FakeTripRepository()
      ..uploadError = const ApiException('expired', statusCode: 401);
    final queue = MemoryLocationQueue();
    final location = FakeLocationService();
    final controller = TripTrackingController(
      repository: repository,
      queue: queue,
      locationService: location,
      session: session,
    );

    await controller.startTracking(repository.trip);

    expect(controller.state, TripTrackingState.authRequired);
    expect(session.user, isNull);
    expect(await queue.count(repository.trip.id), 1);
    controller.dispose();
    await location.close();
  });

  test(
    'terminal 409 reconciliation stops stream and clears trip queue',
    () async {
      final session = await signedInSession();
      final repository = FakeTripRepository()
        ..uploadError = const ApiException('ended', statusCode: 409)
        ..terminalOnReconcile = true;
      final queue = MemoryLocationQueue();
      final location = FakeLocationService();
      final controller = TripTrackingController(
        repository: repository,
        queue: queue,
        locationService: location,
        session: session,
      );

      await controller.startTracking(repository.trip);

      expect(controller.state, TripTrackingState.assignmentEnded);
      expect(await queue.count(repository.trip.id), 0);
      expect(location.streamStarts, 0);
      controller.dispose();
      await location.close();
    },
  );

  for (final scenario in <({int status, TripTrackingState expected})>[
    (status: 400, expected: TripTrackingState.fatalError),
    (status: 403, expected: TripTrackingState.fatalError),
    (status: 404, expected: TripTrackingState.assignmentEnded),
    (status: 422, expected: TripTrackingState.fatalError),
  ]) {
    test(
      'HTTP ${scenario.status} stops unsafe retries with a clear state',
      () async {
        final session = await signedInSession();
        final repository = FakeTripRepository()
          ..uploadError = ApiException('rejected', statusCode: scenario.status);
        final queue = MemoryLocationQueue();
        final location = FakeLocationService();
        final controller = TripTrackingController(
          repository: repository,
          queue: queue,
          locationService: location,
          session: session,
        );

        await controller.startTracking(repository.trip);

        expect(controller.state, scenario.expected);
        expect(controller.diagnostic, isNotEmpty);
        expect(location.streamStarts, 0);
        if (scenario.status == 422) {
          expect(await queue.oldestBatch(repository.trip.id), isEmpty);
        } else {
          expect(await queue.count(repository.trip.id), 1);
        }
        controller.dispose();
        await location.close();
      },
    );
  }

  test(
    'timestamp error code shows clock guidance instead of a generic 422',
    () async {
      final session = await signedInSession();
      final repository = FakeTripRepository()
        ..uploadError = const ApiException(
          'Location timestamp rejected',
          statusCode: 422,
          code: 'LOCATION_TIMESTAMP_INVALID',
        );
      final location = FakeLocationService();
      final controller = TripTrackingController(
        repository: repository,
        queue: MemoryLocationQueue(),
        locationService: location,
        session: session,
      );

      await controller.startTracking(repository.trip);

      expect(controller.diagnostic, contains('automatic date and time'));
      expect(controller.latitude, 23.259933);
      expect(controller.longitude, 77.412615);
      controller.dispose();
      await location.close();
    },
  );
}

Future<SessionController> signedInSession() async {
  final session = SessionController(
    ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          '{"token":"driver-token","user":{"id":"user-1","name":"Raven","email":"driver@example.com","role":"DRIVER","organizationId":"org-1","organizationName":"TransitOps","driverId":"driver-1","mustChangePassword":false}}',
          200,
        ),
      ),
    ),
    tokenStore: MemorySessionTokenStore(),
  );
  expect(
    await session.login(
      email: 'driver@example.com',
      password: 'Password9',
      driverLogin: true,
    ),
    isTrue,
  );
  return session;
}

class FakeTripRepository implements DriverTripGateway {
  DriverTrip trip = DriverTrip(
    trip: Trip(
      id: 'trip-1',
      tripNo: 'AT-2026-023',
      source: 'Bhopal',
      destination: 'Indore',
      cargoWeightKg: 1000,
      plannedDistanceKm: 190,
      revenue: 20000,
      status: 'DISPATCHED',
      vehicle: const Vehicle(
        id: 'vehicle-1',
        registrationNo: 'MP04AB1234',
        name: 'Tata Prima',
        type: 'Truck',
        capacityKg: 16000,
        odometerKm: 42000,
        acquisitionCost: 2000000,
        status: 'ON_TRIP',
        region: 'Central',
      ),
      driver: Driver(
        id: 'driver-1',
        name: 'Raven',
        licenseNo: 'MP-123',
        licenseCategory: 'HMV',
        licenseExpiry: DateTime.utc(2030),
        contact: '0000000000',
        safetyScore: 90,
        status: 'ON_TRIP',
      ),
      createdAt: DateTime.utc(2026, 9, 1),
    ),
  );
  ApiException? uploadError;
  bool terminalOnReconcile = false;
  int fetchCount = 0;
  final List<String> uploadedIds = [];

  @override
  Future<List<DriverTrip>> fetchAssignments() async => [trip];

  @override
  Future<DriverTrip> fetchAssignment(String tripId) async {
    fetchCount++;
    if (terminalOnReconcile && fetchCount > 1) {
      trip = trip.withStatus('COMPLETED');
    }
    return trip;
  }

  @override
  Future<LocationUploadResult> uploadLocations(
    String tripId,
    List<LocationSample> points,
  ) async {
    uploadedIds.addAll(points.map((point) => point.clientRequestId));
    if (uploadError != null) throw uploadError!;
    trip = trip.withStatus('IN_PROGRESS');
    return LocationUploadResult(
      accepted: points.length,
      duplicates: 0,
      tripStatus: 'IN_PROGRESS',
      acknowledgedAt: DateTime.now().toUtc(),
    );
  }
}

class FakeLocationService implements TripLocationService {
  FakeLocationService({this.permission = TrackingPermissionState.always}) {
    _positions = StreamController.broadcast(onCancel: () => cancelled = true);
  }

  TrackingPermissionState permission;
  int streamStarts = 0;
  bool cancelled = false;
  late final StreamController<Position> _positions;

  Position get fix => Position(
    longitude: 77.412615,
    latitude: 23.259933,
    timestamp: DateTime.now().toUtc(),
    accuracy: 11.4,
    altitude: 523,
    altitudeAccuracy: 2,
    heading: 118,
    headingAccuracy: 2,
    speed: 10,
    speedAccuracy: 1,
  );

  @override
  Future<Position> acquireInitialFix() async => fix;

  @override
  Future<void> openSettings() async {}

  @override
  Future<TrackingPermissionState> permissionState() async => permission;

  @override
  Stream<Position> positionStream(String tripNumber) {
    streamStarts++;
    return _positions.stream.transform(
      StreamTransformer.fromHandlers(
        handleDone: (sink) {
          cancelled = true;
          sink.close();
        },
      ),
    );
  }

  @override
  Future<TrackingPermissionState> requestForegroundPermission() async =>
      permission;

  Future<void> close() async {
    cancelled = true;
    await _positions.close();
  }
}
