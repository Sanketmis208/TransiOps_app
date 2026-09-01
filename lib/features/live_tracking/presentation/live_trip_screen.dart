import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../widgets/common.dart';
import '../../driver_trips/models/driver_trip.dart';
import '../controllers/trip_tracking_controller.dart';
import '../services/trip_location_service.dart';

class LiveTripScreen extends StatefulWidget {
  const LiveTripScreen({super.key, required this.trip});

  final DriverTrip trip;

  @override
  State<LiveTripScreen> createState() => _LiveTripScreenState();
}

class _LiveTripScreenState extends State<LiveTripScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TripTrackingController>().prepareTrip(widget.trip.id);
    });
  }

  Future<void> _stop(TripTrackingController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop sharing location?'),
        content: const Text(
          'Dispatch will see this device as offline. The trip remains active until operations completes or cancels it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep sharing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop sharing'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.stop(terminal: false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TripTrackingController>();
    final trip = controller.activeTrip?.id == widget.trip.id
        ? controller.activeTrip!
        : widget.trip;
    final active =
        controller.isActive ||
        controller.state == TripTrackingState.acquiringFix ||
        controller.state == TripTrackingState.stopping;
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Live trip tracking')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          PageHeader(
            eyebrow: 'Assigned trip',
            title: trip.trip.tripNo,
            description:
                '${trip.trip.source} to ${trip.trip.destination}\n${trip.trip.vehicle.name} - ${trip.trip.vehicle.registrationNo}',
          ),
          const SizedBox(height: 18),
          if (!active) _ConsentCard(trip: trip),
          if (active) const _ActiveTrackingCard(),
          if (!active &&
              controller.latitude != null &&
              controller.longitude != null) ...[
            const SizedBox(height: 14),
            const _LastMeasuredPositionCard(),
          ],
          if (controller.diagnostic != null) ...[
            const SizedBox(height: 14),
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.orange),
                    const SizedBox(width: 10),
                    Expanded(child: Text(controller.diagnostic!)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (!active && trip.isTrackable)
            FilledButton.icon(
              onPressed:
                  controller.state == TripTrackingState.acquiringFix ||
                      controller.state == TripTrackingState.stopping
                  ? null
                  : () => controller.startTracking(trip),
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('Start live trip tracking'),
            ),
          if (active) ...[
            OutlinedButton.icon(
              onPressed: controller.state == TripTrackingState.stopping
                  ? null
                  : () => _stop(controller),
              icon: const Icon(Icons.location_off_outlined),
              label: const Text('Stop sharing'),
            ),
          ],
          if (controller.permission == TrackingPermissionState.deniedForever ||
              controller.permission ==
                  TrackingPermissionState.serviceDisabled) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: controller.openLocationSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open location settings'),
            ),
          ],
          if (controller.state == TripTrackingState.activeOffline ||
              controller.state == TripTrackingState.fatalError) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: controller.flush,
              icon: const Icon(Icons.sync),
              label: const Text('Retry synchronization'),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'Privacy: TransitOps collects GPS observations only while this assigned trip is actively sharing. Queued observations are encrypted on this device and cleared after terminal server reconciliation.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.trip});

  final DriverTrip trip;

  @override
  Widget build(BuildContext context) => GlassCard(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Before you start',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const _Reason(
            icon: Icons.visibility_outlined,
            text: 'Live dispatch visibility and ETA coordination',
          ),
          const _Reason(
            icon: Icons.health_and_safety_outlined,
            text: 'Driver safety and an auditable trip trail',
          ),
          const _Reason(
            icon: Icons.timer_outlined,
            text: 'Tracking runs only for this active assigned trip',
          ),
          const _Reason(
            icon: Icons.stop_circle_outlined,
            text: 'Sharing stops when operations completes or cancels the trip',
          ),
          const SizedBox(height: 12),
          const Text(
            'Driver sessions last up to 24 hours. For long journeys, be ready to sign in again; encrypted queued points remain on this device until authentication is restored.',
            style: TextStyle(color: AppColors.orange),
          ),
          const SizedBox(height: 12),
          Text(
            trip.status == 'DISPATCHED'
                ? 'Dispatch is waiting for the first GPS fix. No position is fabricated before you consent.'
                : 'This trip is already in progress. Starting will reconcile with the server before sharing.',
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _Reason extends StatelessWidget {
  const _Reason({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColors.teal),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _ActiveTrackingCard extends StatelessWidget {
  const _ActiveTrackingCard();

  String _time(DateTime? value) => value == null
      ? 'Waiting'
      : DateFormat('HH:mm:ss').format(value.toLocal());

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TripTrackingController>();
    final online = controller.state == TripTrackingState.activeOnline;
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  online ? Icons.sensors : Icons.cloud_off_outlined,
                  color: online ? AppColors.teal : AppColors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    controller.displayStatus,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _Metric('Last captured', _time(controller.lastCapturedAt)),
            _Metric(
              'Server acknowledged',
              _time(controller.lastAcknowledgedAt),
            ),
            _Metric(
              'GPS accuracy',
              controller.accuracyM == null
                  ? 'Waiting'
                  : '${controller.accuracyM!.round()} m',
            ),
            _Metric(
              'Latitude',
              controller.latitude?.toStringAsFixed(6) ?? 'Waiting',
            ),
            _Metric(
              'Longitude',
              controller.longitude?.toStringAsFixed(6) ?? 'Waiting',
            ),
            _Metric(
              'Current speed',
              controller.speedKph == null
                  ? 'Unavailable'
                  : '${controller.speedKph!.toStringAsFixed(1)} km/h',
            ),
            _Metric('Securely queued', '${controller.queuedPoints} points'),
            _Metric(
              'Background indicator',
              controller.isActive ? 'Active' : 'Not active',
            ),
            if (controller.downsampledPoints > 0)
              _Metric(
                'Queue downsampling',
                '${controller.downsampledPoints} old points removed',
              ),
          ],
        ),
      ),
    );
  }
}

class _LastMeasuredPositionCard extends StatelessWidget {
  const _LastMeasuredPositionCard();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TripTrackingController>();
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Phone GPS position',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _Metric(
              'Latitude',
              controller.latitude?.toStringAsFixed(6) ?? 'Unavailable',
            ),
            _Metric(
              'Longitude',
              controller.longitude?.toStringAsFixed(6) ?? 'Unavailable',
            ),
            _Metric(
              'Measured accuracy',
              controller.accuracyM == null
                  ? 'Unavailable'
                  : '${controller.accuracyM!.round()} m',
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
