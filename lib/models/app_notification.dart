class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.data,
    this.tripId,
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String message;
  final String? tripId;
  final DateTime? readAt;
  final DateTime createdAt;
  final Map<String, String> data;

  bool get unread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return AppNotification(
      id: json['id'].toString(),
      type: json['type'].toString(),
      title: json['title'].toString(),
      message: json['message'].toString(),
      tripId: json['tripId']?.toString(),
      readAt: json['readAt'] == null
          ? null
          : DateTime.parse(json['readAt'].toString()).toLocal(),
      createdAt: DateTime.parse(json['createdAt'].toString()).toLocal(),
      data: rawData is Map
          ? rawData.map((key, value) => MapEntry('$key', '$value'))
          : const {},
    );
  }
}
