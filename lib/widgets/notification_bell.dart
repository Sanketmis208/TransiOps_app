import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/push_notification_controller.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final push = context.watch<PushNotificationController>();
    final icon = IconButton(
      tooltip: 'Open notifications',
      onPressed: push.openInbox,
      icon: const Icon(Icons.notifications_outlined),
    );
    if (push.unreadCount == 0) return icon;
    return Badge(
      alignment: const Alignment(.55, -.55),
      label: Text(push.unreadCount > 99 ? '99+' : '${push.unreadCount}'),
      child: icon,
    );
  }
}
