import 'package:flutter_test/flutter_test.dart';
import 'package:transi_ops_app/features/live_tracking/data/location_queue.dart';
import 'package:transi_ops_app/features/live_tracking/domain/location_sample.dart';

LocationSample sample(String id, int second) => LocationSample(
  clientRequestId: id,
  tripId: 'trip-1',
  latitude: 23,
  longitude: 77,
  accuracyM: 10,
  capturedAt: DateTime.utc(2026, 9, 1, 12, 0, second),
);

void main() {
  test(
    'orders oldest first, caps batches, and deletes exact acknowledgements',
    () async {
      final queue = MemoryLocationQueue();
      await queue.enqueue(sample('third', 3));
      await queue.enqueue(sample('first', 1));
      await queue.enqueue(sample('second', 2));

      final batch = await queue.oldestBatch('trip-1', limit: 2);
      expect(batch.map((point) => point.clientRequestId), ['first', 'second']);

      await queue.acknowledge('trip-1', ['first']);
      expect(
        (await queue.oldestBatch(
          'trip-1',
        )).map((point) => point.clientRequestId),
        ['second', 'third'],
      );
    },
  );

  test(
    'deduplicates stable IDs and deterministically downsamples at cap',
    () async {
      final queue = MemoryLocationQueue(maxPoints: 3);
      expect((await queue.enqueue(sample('same', 0))).inserted, isTrue);
      expect((await queue.enqueue(sample('same', 0))).inserted, isFalse);
      await queue.enqueue(sample('two', 2));
      await queue.enqueue(sample('three', 3));
      final result = await queue.enqueue(sample('four', 4));

      expect(result.dropped, 1);
      expect(await queue.count('trip-1'), 3);
      expect(
        (await queue.oldestBatch(
          'trip-1',
        )).map((point) => point.clientRequestId),
        ['same', 'three', 'four'],
      );
    },
  );
}
