class StudyBlockLog {
  final String id;
  final String subject;
  final DateTime timestamp;
  final int durationMinutes;
  final int fatigueScore;
  final int memorySpills;
  final String breadcrumb;

  StudyBlockLog({
    required this.id,
    required this.subject,
    required this.timestamp,
    required this.durationMinutes,
    required this.fatigueScore,
    required this.memorySpills,
    required this.breadcrumb,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject': subject,
      'timestamp': timestamp.toIso8601String(),
      'durationMinutes': durationMinutes,
      'fatigueScore': fatigueScore,
      'memorySpills': memorySpills,
      'breadcrumb': breadcrumb,
    };
  }

  factory StudyBlockLog.fromMap(Map<dynamic, dynamic> map) {
    return StudyBlockLog(
      id: map['id']?.toString() ?? '',
      subject: map['subject']?.toString() ?? 'Physics',
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 75,
      fatigueScore: (map['fatigueScore'] as num?)?.toInt() ?? 3,
      memorySpills: (map['memorySpills'] as num?)?.toInt() ?? 0,
      breadcrumb: map['breadcrumb']?.toString() ?? '',
    );
  }
}

class FeedbackItem {
  final String sender;
  final String category;
  final int rating;
  final String message;

  FeedbackItem({
    required this.sender,
    required this.category,
    required this.rating,
    required this.message,
  });

  factory FeedbackItem.fromMap(Map<dynamic, dynamic> map) {
    return FeedbackItem(
      sender: map['sender']?.toString() ?? 'Anonymous',
      category: map['category']?.toString() ?? 'General',
      rating: (map['rating'] as num?)?.toInt() ?? 5,
      message: map['message']?.toString() ?? '',
    );
  }
}