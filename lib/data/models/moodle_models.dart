class MoodleCourse {
  const MoodleCourse({
    required this.id,
    required this.shortname,
    required this.fullname,
  });

  final int id;
  final String shortname;
  final String fullname;

  factory MoodleCourse.fromJson(Map<String, dynamic> json) => MoodleCourse(
        id: json['id'] as int,
        shortname: (json['shortname'] as String?) ?? '',
        fullname: (json['fullname'] as String?) ?? '',
      );
}

class MoodleStudent {
  const MoodleStudent({
    required this.id,
    required this.fullname,
    required this.email,
  });

  final int id;
  final String fullname;
  final String email;

  factory MoodleStudent.fromJson(Map<String, dynamic> json) => MoodleStudent(
        id: json['id'] as int,
        fullname: (json['fullname'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
      );
}

class MoodleGradeItem {
  const MoodleGradeItem({
    required this.id,
    required this.name,
    required this.itemType,
    this.itemModule,
    this.itemInstance,
    required this.itemNumber,
    required this.gradeMax,
    this.locked = false,
  });

  final int id;
  final String name;
  final String itemType; // 'mod', 'manual', 'course', 'category'
  final String? itemModule; // 'assign', 'quiz', etc.
  final int? itemInstance; // module instance id for mod items
  final int itemNumber;
  final double gradeMax;

  /// True if this grade item is locked in the Moodle gradebook.
  /// Locked items require the 'moodle/grade:override' capability or unlocking.
  final bool locked;

  bool get isManual => itemType == 'manual';

  /// Returns true for items that can be shown in the grade-item picker.
  bool get isSubmittable =>
      (itemType == 'mod' && itemModule != null && itemInstance != null) ||
      itemType == 'manual';

  String get displayType {
    if (itemType == 'mod') return itemModule ?? 'modulo';
    if (itemType == 'manual') return 'manual';
    return itemType;
  }

  factory MoodleGradeItem.fromJson(Map<String, dynamic> json) {
    // 'locked' at item level (not per-student) may be a timestamp (int) or bool.
    final rawLocked = json['locked'];
    final isLocked =
        rawLocked == true || (rawLocked is num && rawLocked > 0);

    return MoodleGradeItem(
      id: json['id'] as int,
      name: (json['itemname'] as String?) ?? 'Item',
      itemType: (json['itemtype'] as String?) ?? '',
      itemModule: json['itemmodule'] as String?,
      itemInstance: json['iteminstance'] as int?,
      itemNumber: (json['itemnumber'] as int?) ?? 0,
      gradeMax: ((json['grademax'] as num?) ?? 100).toDouble(),
      locked: isLocked,
    );
  }
}

class MoodleSession {
  const MoodleSession({
    required this.baseUrl,
    required this.token,
    required this.userId,
    required this.fullname,
    this.serviceName = 'moodle_mobile_app',
  });

  final String baseUrl;
  final String token;
  final int userId;
  final String fullname;

  /// The Moodle external-service name used to obtain this token.
  /// To update grades the service must include:
  ///   mod_assign_save_grade  (for Tarefa/Assign items)
  ///   core_grades_update_grades  (for other items)
  final String serviceName;
}
