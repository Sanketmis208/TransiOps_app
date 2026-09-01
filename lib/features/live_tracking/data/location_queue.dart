import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/location_sample.dart';

class QueueInsertResult {
  const QueueInsertResult({required this.inserted, required this.dropped});
  final bool inserted;
  final int dropped;
}

abstract interface class LocationQueue {
  Future<QueueInsertResult> enqueue(LocationSample sample);
  Future<List<LocationSample>> oldestBatch(String tripId, {int limit = 50});
  Future<void> acknowledge(String tripId, Iterable<String> ids);
  Future<void> quarantine(String tripId, Iterable<String> ids);
  Future<int> count(String tripId);
  Future<void> clearTrip(String tripId);
}

class MemoryLocationQueue implements LocationQueue {
  MemoryLocationQueue({this.maxPoints = 1000});

  final int maxPoints;
  final Map<String, LocationSample> _samples = {};
  final Set<String> _quarantined = {};

  @override
  Future<QueueInsertResult> enqueue(LocationSample sample) async {
    if (_samples.containsKey(sample.clientRequestId)) {
      return const QueueInsertResult(inserted: false, dropped: 0);
    }
    _samples[sample.clientRequestId] = sample;
    final tripSamples = _ordered(sample.tripId);
    var dropped = 0;
    while (tripSamples.length > maxPoints) {
      final index = tripSamples.length > 2 ? 1 : 0;
      final removed = tripSamples.removeAt(index);
      _samples.remove(removed.clientRequestId);
      _quarantined.remove(removed.clientRequestId);
      dropped++;
    }
    return QueueInsertResult(inserted: true, dropped: dropped);
  }

  List<LocationSample> _ordered(String tripId) =>
      _samples.values
          .where(
            (sample) =>
                sample.tripId == tripId &&
                !_quarantined.contains(sample.clientRequestId),
          )
          .toList()
        ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));

  @override
  Future<List<LocationSample>> oldestBatch(
    String tripId, {
    int limit = 50,
  }) async => _ordered(tripId).take(limit.clamp(1, 50)).toList();

  @override
  Future<void> acknowledge(String tripId, Iterable<String> ids) async {
    for (final id in ids) {
      if (_samples[id]?.tripId == tripId) _samples.remove(id);
      _quarantined.remove(id);
    }
  }

  @override
  Future<void> quarantine(String tripId, Iterable<String> ids) async {
    for (final id in ids) {
      if (_samples[id]?.tripId == tripId) _quarantined.add(id);
    }
  }

  @override
  Future<int> count(String tripId) async => _ordered(tripId).length;

  @override
  Future<void> clearTrip(String tripId) async {
    final ids = _samples.values
        .where((sample) => sample.tripId == tripId)
        .map((sample) => sample.clientRequestId)
        .toList();
    for (final id in ids) {
      _samples.remove(id);
      _quarantined.remove(id);
    }
  }
}

class SqlCipherLocationQueue implements LocationQueue {
  SqlCipherLocationQueue({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _databaseKeyName = 'transitops_location_queue_key';
  static const _maxPoints = 1000;
  static const _maxAge = Duration(hours: 24);
  final FlutterSecureStorage _secureStorage;
  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    var password = await _secureStorage.read(key: _databaseKeyName);
    if (password == null) {
      password = const Uuid().v4() + const Uuid().v4();
      await _secureStorage.write(
        key: _databaseKeyName,
        value: password,
        aOptions: const AndroidOptions(),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
    }
    final directory = await getApplicationSupportDirectory();
    _database = await openDatabase(
      p.join(directory.path, 'transitops-location-queue.db'),
      password: password,
      version: 1,
      onCreate: (db, _) => db
          .execute('''
        CREATE TABLE location_points (
          client_request_id TEXT PRIMARY KEY,
          trip_id TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          accuracy_m REAL NOT NULL,
          speed_kph REAL,
          heading_deg REAL,
          altitude_m REAL,
          battery_pct INTEGER,
          is_mocked INTEGER,
          captured_at INTEGER NOT NULL,
          quarantined INTEGER NOT NULL DEFAULT 0
        )
      ''')
          .then(
            (_) => db.execute(
              'CREATE INDEX location_points_trip_time ON location_points(trip_id, captured_at)',
            ),
          ),
    );
    return _database!;
  }

  @override
  Future<QueueInsertResult> enqueue(LocationSample sample) async {
    final db = await _db;
    final inserted =
        await db.insert(
          'location_points',
          sample.toDatabaseMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        ) !=
        0;
    final dropped = await _prune(db, sample.tripId);
    return QueueInsertResult(inserted: inserted, dropped: dropped);
  }

  Future<int> _prune(Database db, String tripId) async {
    var dropped = await db.delete(
      'location_points',
      where: 'trip_id = ? AND captured_at < ?',
      whereArgs: [
        tripId,
        DateTime.now().toUtc().subtract(_maxAge).millisecondsSinceEpoch,
      ],
    );
    var total = await count(tripId);
    while (total > _maxPoints) {
      final excess = total - _maxPoints;
      final candidates = await db.query(
        'location_points',
        columns: ['client_request_id'],
        where: 'trip_id = ? AND quarantined = 0',
        whereArgs: [tripId],
        orderBy: 'captured_at ASC',
        limit: min(max(excess * 2, 20), 200),
      );
      final ids = <String>[
        for (var index = 0; index < candidates.length; index += 2)
          candidates[index]['client_request_id'] as String,
      ].take(excess).toList();
      if (ids.isEmpty) break;
      dropped += await _deleteIds(db, tripId, ids);
      total = await count(tripId);
    }
    return dropped;
  }

  @override
  Future<List<LocationSample>> oldestBatch(
    String tripId, {
    int limit = 50,
  }) async => (await (await _db).query(
    'location_points',
    where: 'trip_id = ? AND quarantined = 0',
    whereArgs: [tripId],
    orderBy: 'captured_at ASC',
    limit: limit.clamp(1, 50),
  )).map(LocationSample.fromDatabaseMap).toList(growable: false);

  @override
  Future<void> acknowledge(String tripId, Iterable<String> ids) async {
    await _deleteIds(await _db, tripId, ids.toList());
  }

  Future<int> _deleteIds(Database db, String tripId, List<String> ids) {
    if (ids.isEmpty) return Future.value(0);
    return db.delete(
      'location_points',
      where:
          'trip_id = ? AND client_request_id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: [tripId, ...ids],
    );
  }

  @override
  Future<void> quarantine(String tripId, Iterable<String> ids) async {
    final values = ids.toList();
    if (values.isEmpty) return;
    await (await _db).update(
      'location_points',
      {'quarantined': 1},
      where:
          'trip_id = ? AND client_request_id IN (${List.filled(values.length, '?').join(',')})',
      whereArgs: [tripId, ...values],
    );
  }

  @override
  Future<int> count(String tripId) async =>
      Sqflite.firstIntValue(
        await (await _db).rawQuery(
          'SELECT COUNT(*) FROM location_points WHERE trip_id = ? AND quarantined = 0',
          [tripId],
        ),
      ) ??
      0;

  @override
  Future<void> clearTrip(String tripId) async {
    await (await _db).delete(
      'location_points',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
  }
}
