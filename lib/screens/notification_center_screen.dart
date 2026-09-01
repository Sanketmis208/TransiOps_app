import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/push_notification_controller.dart';
import '../core/session_controller.dart';
import '../models/app_notification.dart';
import '../widgets/common.dart';
import 'drivers_screen.dart';
import 'finance_screen.dart';
import 'maintenance_screen.dart';
import 'trips_screen.dart';

class NotificationCenterScreen extends StatelessWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PushNotificationController>();
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Notifications'),
        actions: [
          if (controller.unreadCount > 0)
            TextButton(
              onPressed: controller.markAllRead,
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: controller.items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 120),
                  Icon(
                    Icons.notifications_none,
                    size: 52,
                    color: AppColors.muted.withValues(alpha: .7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    controller.loading
                        ? 'Loading notifications...'
                        : 'You are all caught up',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (controller.error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      controller.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.red),
                    ),
                  ],
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
                itemCount: controller.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final item = controller.items[index];
                  return GlassCard(
                    opacity: item.unread ? .84 : .62,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: _color(item).withValues(alpha: .12),
                        child: Icon(_icon(item), color: _color(item)),
                      ),
                      title: Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: item.unread
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          '${item.message}\n${DateFormat('dd MMM, h:mm a').format(item.createdAt)}',
                        ),
                      ),
                      isThreeLine: true,
                      trailing: item.unread
                          ? const Icon(
                              Icons.circle,
                              size: 9,
                              color: AppColors.orange,
                            )
                          : null,
                      onTap: () => _open(context, controller, item),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    PushNotificationController controller,
    AppNotification item,
  ) async {
    await controller.markRead(item);
    if (!context.mounted) return;
    final user = context.read<SessionController>().user;
    if (user == null || user.role.apiValue == 'DRIVER') {
      Navigator.pop(context);
      return;
    }
    final screen = item.data['screen'];
    final Widget? destination = switch (screen) {
      'trip' => const TripsScreen(),
      'expense' => const FinanceScreen(),
      'maintenance' => const MaintenanceScreen(),
      'driver-review' => const DriversScreen(),
      _ => null,
    };
    if (destination != null) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => destination),
      );
    }
  }

  IconData _icon(AppNotification item) {
    if (item.type.startsWith('TRIP_')) return Icons.route_outlined;
    if (item.type.startsWith('DRIVER_ONBOARDING')) return Icons.badge_outlined;
    if (item.type == 'DRIVER_EXPENSE_SUBMITTED') {
      return Icons.receipt_long_outlined;
    }
    return Icons.build_outlined;
  }

  Color _color(AppNotification item) {
    if (item.type.endsWith('COMPLETED') || item.type.endsWith('APPROVED')) {
      return AppColors.green;
    }
    if (item.type.endsWith('CANCELLED') || item.type.endsWith('REJECTED')) {
      return AppColors.red;
    }
    return AppColors.orange;
  }
}
