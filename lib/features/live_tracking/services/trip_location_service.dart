import 'dart:io';

import 'package:geolocator/geolocator.dart';

enum TrackingPermissionState {
  unknown,
  serviceDisabled,
  denied,
  deniedForever,
  foreground,
  always,
}

abstract interface class TripLocationService {
  Future<TrackingPermissionState> permissionState();
  Future<TrackingPermissionState> requestForegroundPermission();
  Future<Position> acquireInitialFix();
  Stream<Position> positionStream(String tripNumber);
  Future<void> openSettings();
}

class GeolocatorTripLocationService implements TripLocationService {
  @override
  Future<TrackingPermissionState> permissionState() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return TrackingPermissionState.serviceDisabled;
    }
    return _mapPermission(await Geolocator.checkPermission());
  }

  @override
  Future<TrackingPermissionState> requestForegroundPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return TrackingPermissionState.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return _mapPermission(permission);
  }

  TrackingPermissionState _mapPermission(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always => TrackingPermissionState.always,
        LocationPermission.whileInUse => TrackingPermissionState.foreground,
        LocationPermission.deniedForever =>
          TrackingPermissionState.deniedForever,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => TrackingPermissionState.denied,
      };

  @override
  Future<Position> acquireInitialFix() => Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      timeLimit: Duration(seconds: 30),
    ),
  );

  @override
  Stream<Position> positionStream(String tripNumber) {
    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'TransitOps live trip tracking',
          notificationText: 'Sharing location for trip $tripNumber',
          notificationChannelName: 'Active trip location',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (Platform.isIOS || Platform.isMacOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 25,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 25,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  @override
  Future<void> openSettings() async {
    if (!await Geolocator.openAppSettings()) {
      await Geolocator.openLocationSettings();
    }
  }
}
