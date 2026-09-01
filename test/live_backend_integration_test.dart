import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transi_ops_app/core/api_client.dart';
import 'package:transi_ops_app/core/auth/driver_session_store.dart';
import 'package:transi_ops_app/core/session_controller.dart';
import 'package:transi_ops_app/features/driver_trips/data/driver_trip_repository.dart';
import 'package:transi_ops_app/features/live_tracking/domain/location_sample.dart';

const _runLiveIntegration = bool.fromEnvironment('RUN_LIVE_INTEGRATION');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Flutter driver client exchanges the production contract with FleetPilot',
    () async {
      final testHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = testHttpOverrides);
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient();
      final session = SessionController(
        api,
        tokenStore: MemorySessionTokenStore(),
      );
      expect(
        await session.login(
          email: 'verified.driver.integration@transitops.test',
          password: 'Integration@123',
          driverLogin: true,
        ),
        isTrue,
      );
      expect(session.user?.driverId, 'integration-driver');

      final repository = DriverTripRepository(api);
      final assignments = await repository.fetchAssignments();
      final active = assignments.singleWhere(
        (trip) => trip.id == 'integration-trip-dispatched',
      );
      expect(active.status, 'DISPATCHED');
      final detail = await repository.fetchAssignment(active.id);
      expect(detail.tracking?.status, 'WAITING_FOR_GPS');
      expect(detail.tracking?.latestLocation, isNull);

      final uploaded = await repository.uploadLocations(active.id, [
        LocationSample(
          clientRequestId: 'flutter-live-integration-point-0001',
          tripId: active.id,
          latitude: 23.259933,
          longitude: 77.412615,
          accuracyM: 11.4,
          speedKph: 42.7,
          headingDeg: 118,
          altitudeM: 523.2,
          batteryPct: 71,
          isMocked: false,
          capturedAt: DateTime.now().toUtc(),
        ),
      ]);
      expect(uploaded.accepted, 1);
      expect(uploaded.tripStatus, 'IN_PROGRESS');

      final reconciled = await repository.fetchAssignment(active.id);
      expect(reconciled.status, 'IN_PROGRESS');
      expect(reconciled.tracking?.status, 'LIVE');
      expect(reconciled.tracking?.latestLocation?.latitude, 23.259933);
      await session.logout();
    },
    skip: !_runLiveIntegration,
  );
}
