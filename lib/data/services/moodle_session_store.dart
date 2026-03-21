import 'package:shared_preferences/shared_preferences.dart';

import '../models/moodle_models.dart';

class MoodleSessionStore {
  static const _kBaseUrl = 'moodle_base_url';
  static const _kToken = 'moodle_token';
  static const _kUserId = 'moodle_user_id';
  static const _kFullname = 'moodle_fullname';
  static const _kServiceName = 'moodle_service_name';
  static const _kAvailableFunctions = 'moodle_available_functions';
  static const _kCourseId = 'moodle_course_id';
  static const _kCourseShortname = 'moodle_course_shortname';
  static const _kCourseFullname = 'moodle_course_fullname';
  static const _kItemId = 'moodle_item_id';
  static const _kItemName = 'moodle_item_name';
  static const _kItemType = 'moodle_item_type';
  static const _kItemModule = 'moodle_item_module';
  static const _kItemInstance = 'moodle_item_instance';
  static const _kItemNumber = 'moodle_item_number';
  static const _kItemGradeMax = 'moodle_item_grade_max';

  Future<MoodleSession?> loadSession() async {
    final p = await SharedPreferences.getInstance();
    final baseUrl = p.getString(_kBaseUrl);
    final token = p.getString(_kToken);
    final userId = p.getInt(_kUserId);
    if (baseUrl == null || token == null || userId == null) return null;
    return MoodleSession(
      baseUrl: baseUrl,
      token: token,
      userId: userId,
      fullname: p.getString(_kFullname) ?? '',
      serviceName: p.getString(_kServiceName) ?? 'moodle_mobile_app',
      availableFunctions: (p.getStringList(_kAvailableFunctions) ?? []).toSet(),
    );
  }

  Future<void> saveSession(MoodleSession s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBaseUrl, s.baseUrl);
    await p.setString(_kToken, s.token);
    await p.setInt(_kUserId, s.userId);
    await p.setString(_kFullname, s.fullname);
    await p.setString(_kServiceName, s.serviceName);
    await p.setStringList(_kAvailableFunctions, s.availableFunctions.toList());
  }

  Future<MoodleCourse?> loadCourse() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getInt(_kCourseId);
    if (id == null) return null;
    return MoodleCourse(
      id: id,
      shortname: p.getString(_kCourseShortname) ?? '',
      fullname: p.getString(_kCourseFullname) ?? '',
    );
  }

  Future<void> saveCourse(MoodleCourse c) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCourseId, c.id);
    await p.setString(_kCourseShortname, c.shortname);
    await p.setString(_kCourseFullname, c.fullname);
  }

  Future<MoodleGradeItem?> loadGradeItem() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getInt(_kItemId);
    if (id == null) return null;
    return MoodleGradeItem(
      id: id,
      name: p.getString(_kItemName) ?? '',
      itemType: p.getString(_kItemType) ?? '',
      itemModule: p.getString(_kItemModule),
      itemInstance: p.getInt(_kItemInstance),
      itemNumber: p.getInt(_kItemNumber) ?? 0,
      gradeMax: p.getDouble(_kItemGradeMax) ?? 100,
    );
  }

  Future<void> saveGradeItem(MoodleGradeItem item) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kItemId, item.id);
    await p.setString(_kItemName, item.name);
    await p.setString(_kItemType, item.itemType);
    if (item.itemModule != null) {
      await p.setString(_kItemModule, item.itemModule!);
    }
    if (item.itemInstance != null) {
      await p.setInt(_kItemInstance, item.itemInstance!);
    }
    await p.setInt(_kItemNumber, item.itemNumber);
    await p.setDouble(_kItemGradeMax, item.gradeMax);
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    for (final key in [
      _kBaseUrl,
      _kToken,
      _kUserId,
      _kFullname,
      _kServiceName,
      _kAvailableFunctions,
      _kCourseId,
      _kCourseShortname,
      _kCourseFullname,
      _kItemId,
      _kItemName,
      _kItemType,
      _kItemModule,
      _kItemInstance,
      _kItemNumber,
      _kItemGradeMax,
    ]) {
      await p.remove(key);
    }
  }
}
