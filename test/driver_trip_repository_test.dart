import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transi_ops_app/core/api_client.dart';
import 'package:transi_ops_app/features/driver_trips/data/driver_trip_repository.dart';
import 'package:transi_ops_app/features/live_tracking/domain/location_sample.dart';

void main() {
  final tripJson = {
    'id': 'trip-1',
    'tripNo': 'IT-LIVE-001',
    'source': 'Bhopal Depot',
    'destination': 'Indore Warehouse',
    'cargoWeightKg': 8000,
    'plannedDistanceKm': 195,
    'revenue': 42000,
    'status': 'DISPATCHED',
    'createdAt': '2026-09-01T10:00:00.000Z',
    'vehicle': {
      'id': 'vehicle-1',
      'registrationNo': 'MP04IT0001',
      'name': 'Integration Truck',
      'type': 'Truck',
      'capacityKg': 16000,
      'odometerKm': 42000,
      'acquisitionCost': 2800000,
      'status': 'ON_TRIP',
      'region': 'Central',
    },
    'driver': {
      'id': 'driver-1',
      'name': 'Integration Driver',
      'licenseNo': 'IT-HMV-001',
      'licenseCategory': 'HMV',
      'licenseExpiry': '2032-12-31T00:00:00.000Z',
      'contact': '+91 90000 00001',
      'safetyScore': 100,
      'status': 'ON_TRIP',
    },
  };

  test(
    'uses only driver-scoped assignment endpoints and parses tracking',
    () async {
      final requestedPaths = <String>[];
      final client = ApiClient(
        httpClient: MockClient((request) async {
          requestedPaths.add(request.url.path);
          expect(request.headers['authorization'], 'Bearer driver-token');
          if (request.url.path.endsWith('/driver/me/trips/trip-1')) {
            return http.Response(
              jsonEncode({
                ...tripJson,
                'tracking': {
                  'status': 'WAITING_FOR_GPS',
                  'latestLocation': null,
                },
              }),
              200,
            );
          }
          return http.Response(jsonEncode([tripJson]), 200);
        }),
      )..token = 'driver-token';
      final repository = DriverTripRepository(client);

      final assignments = await repository.fetchAssignments();
      final detail = await repository.fetchAssignment('trip-1');

      expect(assignments.single.trip.tripNo, 'IT-LIVE-001');
      expect(detail.tracking?.status, 'WAITING_FOR_GPS');
      expect(requestedPaths, everyElement(contains('/driver/me/trips')));
      expect(requestedPaths, isNot(contains('/api/trips')));
    },
  );

  test(
    'uploads the exact location contract and accepts server status',
    () async {
      final sample = LocationSample(
        clientRequestId: '550e8400-e29b-41d4-a716-446655440000',
        tripId: 'trip-1',
        latitude: 23.259933,
        longitude: 77.412615,
        accuracyM: 11.4,
        speedKph: 42.7,
        headingDeg: 118,
        altitudeM: 523.2,
        batteryPct: 71,
        isMocked: false,
        capturedAt: DateTime.parse('2026-09-01T12:00:00.000Z'),
      );
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.path,
            endsWith('/driver/me/trips/trip-1/locations'),
          );
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final point =
              (body['points'] as List<dynamic>).single as Map<String, dynamic>;
          expect(point, {
            'clientRequestId': sample.clientRequestId,
            'latitude': 23.259933,
            'longitude': 77.412615,
            'accuracyM': 11.4,
            'speedKph': 42.7,
            'headingDeg': 118.0,
            'altitudeM': 523.2,
            'batteryPct': 71,
            'isMocked': false,
            'capturedAt': '2026-09-01T12:00:00.000Z',
          });
          return http.Response(
            '{"accepted":1,"duplicates":0,"tripStatus":"IN_PROGRESS",'
            '"latestLocation":{"receivedAt":"2026-09-01T12:00:01.000Z"}}',
            201,
          );
        }),
      )..token = 'driver-token';

      final result = await DriverTripRepository(
        client,
      ).uploadLocations('trip-1', [sample]);

      expect(result.accepted, 1);
      expect(result.duplicates, 0);
      expect(result.tripStatus, 'IN_PROGRESS');
      expect(result.acknowledgedAt, DateTime.utc(2026, 9, 1, 12, 0, 1));
    },
  );
}
