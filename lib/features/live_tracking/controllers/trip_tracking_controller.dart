import 'dart:async';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api_client.dart';
import '../../../core/session_controller.dart';
import '../../driver_trips/data/driver_trip_repository.dart';
import '../../driver_trips/models/driver_trip.dart';
import '../data/location_queue.dart';
import '../domain/location_sample.dart';
import '../services/trip_location_service.dart';

enum TripTrackingState {
  idle,
  permissionRequired,
  acquiringFix,
  activeOnline,
  activeOffline,
  stopping,
  stopped,
  authRequired,
  assignmentEnded,
  permissionRevoked,
  fatalError,
}

class TripTrackingController extends ChangeNotifier
    with WidgetsBindingObserver {
  TripTrackingController({
    required DriverTripGateway repository,
    required LocationQueue queue,
    required TripLocationService locationService,
    required SessionController session,
    Battery? battery,
    Connectivity? connectivity,
    Uuid? uuid,
  }) : _repository = repository,
       _queue = queue,
       _locationService = locationService,
       _session = session,
       _battery = battery ?? Battery(),
       _connectivity = connectivity ?? Connectivity(),
       _uuid = uuid ?? const Uuid() {
    _session.addListener(_handleSessionChange);
  }

  static const _activeTripKey = 'transitops_active_tracking_trip';
  static const _consentKey = 'transitops_tracking_consent_version';
  static const _consentVersion = 1;
  static const _uploadIntervals = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  final DriverTripGateway _repository;
  final LocationQueue _queue;
  final TripLocationService _locationService;
  final SessionController _session;
  final Battery _battery;
  final Connectivity _connectivity;
  final Uuid _uuid;

  TripTrackingState state = TripTrackingState.idle;
  TrackingPermissionState permission = TrackingPermissionState.unknown;
  List<DriverTrip> assignments = const [];
  DriverTrip? activeTrip;
  DateTime? lastCapturedAt;
  DateTime? lastAcknowledgedAt;
  double? accuracyM;
  double? speedKph;
  double? latitude;
  double? longitude;
  int queuedPoints = 0;
  int downsampledPoints = 0;
  String? diagnostic;
  bool assignmentsLoading = false;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _visiblePollingTimer;
  Timer? _trackingPollingTimer;
  Timer? _uploadTimer;
  Timer? _retryTimer;
  Position? _lastQueuedPosition;
  DateTime? _lastGoodAccuracyAt;
  DateTime? _stationarySince;
  bool _transitioning = false;
  bool _flushInProgress = false;
  int _retryIndex = 0;
  bool _initialized = false;

  bool get isActive =>
      state == TripTrackingState.activeOnline ||
      state == TripTrackingState.activeOffline;

  String get displayStatus => switch (state) {
    TripTrackingState.activeOnline when queuedPoints == 0 => 'LIVE',
    TripTrackingState.activeOnline => 'SYNCING',
    TripTrackingState.activeOffline => 'OFFLINE - QUEUED',
    TripTrackingState.permissionRequired ||
    TripTrackingState.permissionRevoked => 'GPS PAUSED',
    TripTrackingState.authRequired ||
    TripTrackingState.fatalError => 'ACTION REQUIRED',
    TripTrackingState.acquiringFix => 'ACQUIRING GPS',
    TripTrackingState.stopping => 'STOPPING',
    TripTrackingState.assignmentEnded => 'TRIP ENDED',
    _ => 'NOT SHARING',
  };

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    permission = await _locationService.permissionState();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((_) {
      if (isActive) unawaited(flush());
    });
    await refreshAssignments();
    await _restoreTrackingMarker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshAssignments());
      unawaited(_refreshPermission());
    }
  }

  Future<void> _refreshPermission() async {
    permission = await _locationService.permissionState();
    if (isActive &&
        permission != TrackingPermissionState.foreground &&
        permission != TrackingPermissionState.always) {
      await stop(
        terminal: false,
        finalState: TripTrackingState.permissionRevoked,
        message: 'Location permission was removed. Enable it to resume.',
      );
    }
    notifyListeners();
  }

  void startVisiblePolling() {
    _visiblePollingTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(refreshAssignments()),
    );
    unawaited(refreshAssignments());
  }

  void stopVisiblePolling() {
    _visiblePollingTimer?.cancel();
    _visiblePollingTimer = null;
  }

  Future<void> refreshAssignments() async {
    if (_session.user?.role.name != 'driver' || assignmentsLoading) return;
    assignmentsLoading = true;
    notifyListeners();
    try {
      assignments = await _repository.fetchAssignments();
      final current = activeTrip;
      if (current != null) {
        final serverTrip = assignments
            .where((trip) => trip.id == current.id)
            .firstOrNull;
        if (serverTrip != null) activeTrip = serverTrip;
        if (serverTrip == null || serverTrip.isTerminal) {
          await stop(
            terminal: true,
            finalState: TripTrackingState.assignmentEnded,
            message: 'Operations ended this trip. Location sharing stopped.',
          );
        }
      }
      diagnostic = null;
    } on ApiException catch (error) {
      if (error.statusCode == 401) await _requireAuthentication();
      diagnostic ??= error.message;
    } finally {
      assignmentsLoading = false;
      notifyListeners();
    }
  }

  Future<DriverTrip?> prepareTrip(String tripId) async {
    try {
      final trip = await _repository.fetchAssignment(tripId);
      activeTrip = trip;
      queuedPoints = await _queue.count(tripId);
      notifyListeners();
      return trip;
    } on ApiException catch (error) {
      diagnostic = error.message;
      if (error.statusCode == 401) await _requireAuthentication();
      notifyListeners();
      return null;
    }
  }

  Future<void> startTracking(DriverTrip selectedTrip) async {
    if (_transitioning || _positionSubscription != null) return;
    _transitioning = true;
    diagnostic = null;
    try {
      final reconciled = await _repository.fetchAssignment(selectedTrip.id);
      activeTrip = reconciled;
      if (!reconciled.isTrackable) {
        await stop(
          terminal: reconciled.isTerminal,
          finalState: TripTrackingState.assignmentEnded,
          message: 'This trip is no longer eligible for location sharing.',
        );
        return;
      }
      state = TripTrackingState.acquiringFix;
      notifyListeners();
      permission = await _locationService.requestForegroundPermission();
      if (permission != TrackingPermissionState.foreground &&
          permission != TrackingPermissionState.always) {
        state = TripTrackingState.permissionRequired;
        diagnostic = permission == TrackingPermissionState.serviceDisabled
            ? 'Turn on Location Services to track this trip.'
            : 'Location permission is required only while tracking this trip.';
        notifyListeners();
        return;
      }
      final firstFix = await _locationService.acquireInitialFix();
      accuracyM = firstFix.accuracy;
      await _capture(firstFix, force: true);
      if (activeTrip?.isTrackable != true ||
          state == TripTrackingState.assignmentEnded ||
          state == TripTrackingState.authRequired ||
          state == TripTrackingState.fatalError) {
        return;
      }
      await _positionSubscription?.cancel();
      _positionSubscription = _locationService
          .positionStream(reconciled.trip.tripNo)
          .listen(
            (position) => unawaited(_capture(position)),
            onError: (Object error) => unawaited(
              stop(
                terminal: false,
                finalState: TripTrackingState.permissionRevoked,
                message: 'GPS updates stopped. Check location settings.',
              ),
            ),
          );
      state = TripTrackingState.activeOffline;
      await _saveTrackingMarker(reconciled.id);
      _startTrackingTimers();
      await flush();
    } on ApiException catch (error) {
      await _handleApiError(error, const []);
    } on TimeoutException {
      state = TripTrackingState.permissionRequired;
      diagnostic =
          'A precise GPS fix was not available. Move outdoors and retry.';
    } catch (_) {
      state = TripTrackingState.fatalError;
      diagnostic = 'Live tracking could not start. Check GPS and try again.';
    } finally {
      _transitioning = false;
      notifyListeners();
    }
  }

  void _startTrackingTimers() {
    _uploadTimer?.cancel();
    _trackingPollingTimer?.cancel();
    _uploadTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(flush()),
    );
    _trackingPollingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_reconcileActiveTrip()),
    );
  }

  Future<void> _capture(Position position, {bool force = false}) async {
    final trip = activeTrip;
    if (trip == null || !trip.isTrackable) return;
    if (!LocationSample.validCoordinates(
      position.latitude,
      position.longitude,
    )) {
      return;
    }
    final now = position.timestamp.toUtc();
    final previous = _lastQueuedPosition;
    final elapsed = previous == null
        ? const Duration(days: 1)
        : now.difference(previous.timestamp.toUtc());
    final distance = previous == null
        ? double.infinity
        : Geolocator.distanceBetween(
            previous.latitude,
            previous.longitude,
            position.latitude,
            position.longitude,
          );
    if (previous != null && distance < 25 && position.speed < 1) {
      _stationarySince ??= now;
    } else {
      _stationarySince = null;
    }
    final stationaryForFiveMinutes =
        _stationarySince != null &&
        now.difference(_stationarySince!) >= const Duration(minutes: 5);
    if (!force &&
        stationaryForFiveMinutes &&
        elapsed < const Duration(minutes: 2)) {
      return;
    }
    if (!force && elapsed < const Duration(seconds: 10) && distance < 25) {
      return;
    }
    if (position.accuracy <= 1000) _lastGoodAccuracyAt = DateTime.now().toUtc();
    final noGoodFixForTwoMinutes =
        _lastGoodAccuracyAt == null ||
        DateTime.now().toUtc().difference(_lastGoodAccuracyAt!) >=
            const Duration(minutes: 2);
    if (position.accuracy > 1000 && !noGoodFixForTwoMinutes) return;
    final sample = LocationSample.fromPosition(
      id: _uuid.v4(),
      tripId: trip.id,
      position: position,
      batteryPct: await _safeBatteryLevel(),
    );
    final result = await _queue.enqueue(sample);
    if (!result.inserted) return;
    downsampledPoints += result.dropped;
    _lastQueuedPosition = position;
    lastCapturedAt = sample.capturedAt;
    latitude = sample.latitude;
    longitude = sample.longitude;
    accuracyM = sample.accuracyM;
    speedKph = sample.speedKph;
    queuedPoints = await _queue.count(trip.id);
    notifyListeners();
    if (lastAcknowledgedAt == null) await flush();
  }

  Future<int?> _safeBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  Future<void> flush() async {
    final trip = activeTrip;
    if (_flushInProgress || trip == null || !trip.isTrackable) return;
    _flushInProgress = true;
    try {
      while (true) {
        final batch = await _queue.oldestBatch(trip.id, limit: 50);
        if (batch.isEmpty) {
          queuedPoints = 0;
          if (isActive) state = TripTrackingState.activeOnline;
          break;
        }
        try {
          final response = await _repository.uploadLocations(trip.id, batch);
          await _queue.acknowledge(
            trip.id,
            batch.map((point) => point.clientRequestId),
          );
          activeTrip = trip.withStatus(response.tripStatus);
          lastAcknowledgedAt =
              response.acknowledgedAt ?? DateTime.now().toUtc();
          queuedPoints = await _queue.count(trip.id);
          state = TripTrackingState.activeOnline;
          _retryIndex = 0;
          diagnostic = null;
          notifyListeners();
          if (activeTrip!.isTerminal) {
            await stop(
              terminal: true,
              finalState: TripTrackingState.assignmentEnded,
              message: 'Operations ended this trip. Location sharing stopped.',
            );
            break;
          }
        } on ApiException catch (error) {
          await _handleApiError(error, batch);
          break;
        }
      }
    } finally {
      _flushInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _handleApiError(
    ApiException error,
    List<LocationSample> batch,
  ) async {
    final trip = activeTrip;
    if (trip == null) return;
    switch (error.statusCode) {
      case 400:
        state = TripTrackingState.fatalError;
        diagnostic = 'A location batch was rejected. Tracking paused safely.';
        await _disposeCapture();
      case 401:
        await _requireAuthentication();
      case 403:
        await stop(
          terminal: false,
          finalState: TripTrackingState.fatalError,
          message: 'This account is not eligible to share trip location.',
        );
      case 404:
        const message =
            'The assigned trip could not be found. Assignments refreshed.';
        await stop(
          terminal: false,
          finalState: TripTrackingState.assignmentEnded,
          message: message,
        );
        await refreshAssignments();
        diagnostic = message;
      case 409:
        await _reconcileActiveTrip();
      case 422:
        await _queue.quarantine(
          trip.id,
          batch.map((point) => point.clientRequestId),
        );
        queuedPoints = await _queue.count(trip.id);
        state = TripTrackingState.fatalError;
        diagnostic = error.code == 'LOCATION_TIMESTAMP_INVALID'
            ? 'Device time does not match the trip timeline. Enable automatic date and time.'
            : error.message;
        await _disposeCapture();
        await _reconcileActiveTrip();
      default:
        state = TripTrackingState.activeOffline;
        diagnostic = 'Location is queued securely until the network recovers.';
        _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final base =
        _uploadIntervals[min(_retryIndex, _uploadIntervals.length - 1)];
    _retryIndex++;
    final jitter = Duration(milliseconds: Random().nextInt(750));
    _retryTimer = Timer(base + jitter, () => unawaited(flush()));
  }

  Future<void> _reconcileActiveTrip() async {
    final trip = activeTrip;
    if (trip == null) return;
    try {
      final serverTrip = await _repository.fetchAssignment(trip.id);
      activeTrip = serverTrip;
      if (!serverTrip.isTrackable) {
        await stop(
          terminal: serverTrip.isTerminal,
          finalState: TripTrackingState.assignmentEnded,
          message: 'Operations ended this trip. Location sharing stopped.',
        );
      }
    } on ApiException catch (error) {
      await _handleApiError(error, const []);
    }
    notifyListeners();
  }

  Future<void> stop({
    required bool terminal,
    TripTrackingState finalState = TripTrackingState.stopped,
    String? message,
  }) async {
    if (state == TripTrackingState.stopping) return;
    state = TripTrackingState.stopping;
    notifyListeners();
    final tripId = activeTrip?.id;
    await _disposeCapture();
    if (terminal && tripId != null) await _queue.clearTrip(tripId);
    if (tripId != null) queuedPoints = await _queue.count(tripId);
    await _clearTrackingMarker();
    state = finalState;
    diagnostic = message;
    notifyListeners();
  }

  Future<void> _disposeCapture() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _uploadTimer?.cancel();
    _trackingPollingTimer?.cancel();
    _retryTimer?.cancel();
    _uploadTimer = null;
    _trackingPollingTimer = null;
    _retryTimer = null;
  }

  Future<void> _requireAuthentication() async {
    await _disposeCapture();
    state = TripTrackingState.authRequired;
    diagnostic =
        'Your 24-hour driver session expired. Sign in to resume syncing.';
    await _session.invalidateSession();
  }

  Future<void> _restoreTrackingMarker() async {
    if (_session.user?.role.name != 'driver') return;
    final prefs = await SharedPreferences.getInstance();
    final tripId = prefs.getString(_activeTripKey);
    final consent = prefs.getInt(_consentKey);
    if (tripId == null || consent != _consentVersion) return;
    final trip = await prepareTrip(tripId);
    if (trip != null && trip.isTrackable) await startTracking(trip);
  }

  Future<void> _saveTrackingMarker(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeTripKey, tripId);
    await prefs.setInt(_consentKey, _consentVersion);
  }

  Future<void> _clearTrackingMarker() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeTripKey);
    await prefs.remove(_consentKey);
  }

  void _handleSessionChange() {
    if (_session.user == null && _positionSubscription != null) {
      unawaited(
        stop(
          terminal: false,
          finalState: TripTrackingState.authRequired,
          message: 'Sign in to resume location synchronization.',
        ),
      );
    }
  }

  Future<void> openLocationSettings() => _locationService.openSettings();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_handleSessionChange);
    stopVisiblePolling();
    unawaited(_disposeCapture());
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }
}
