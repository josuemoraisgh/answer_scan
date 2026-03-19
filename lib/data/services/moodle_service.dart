import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/moodle_models.dart';

class MoodleException implements Exception {
  const MoodleException(this.message, {this.errorCode});
  final String message;

  /// Moodle machine-readable error code, e.g. 'accessdenied', 'nopermissions'.
  final String? errorCode;

  @override
  String toString() => message;
}

class MoodleService {
  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Authenticates and returns (token, userId, fullname).
  /// [serviceName] must match an External Service configured in Moodle that
  /// includes all WS functions used by this app.
  Future<(String token, int userId, String fullname)> login({
    required String baseUrl,
    required String username,
    required String password,
    String serviceName = 'moodle_mobile_app',
  }) async {
    final resp = await http.post(
      _uri(baseUrl, 'login/token.php'),
      body: {
        'username': username,
        'password': password,
        'service': serviceName,
      },
    );
    _checkStatus(resp);
    final data = _decode(resp.body) as Map<String, dynamic>;
    if (data.containsKey('error')) {
      throw MoodleException(
        (data['error'] as String?) ?? 'Usuário ou senha inválidos.',
        errorCode: data['errorcode'] as String?,
      );
    }
    final token = data['token'] as String;

    final info = await _ws(baseUrl, token, 'core_webservice_get_site_info')
        as Map<String, dynamic>;
    return (token, info['userid'] as int, (info['fullname'] as String?) ?? '');
  }

  Future<List<MoodleCourse>> getCourses({
    required String baseUrl,
    required String token,
    required int userId,
  }) async {
    final data = await _ws(
      baseUrl,
      token,
      'core_enrol_get_users_courses',
      {'userid': '$userId'},
    ) as List<dynamic>;
    return data
        .map((e) => MoodleCourse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns only grade items that are suitable for the grade picker.
  Future<List<MoodleGradeItem>> getGradeItems({
    required String baseUrl,
    required String token,
    required int courseId,
    required int userId,
  }) async {
    final data = await _ws(
      baseUrl,
      token,
      'gradereport_user_get_grade_items',
      {'courseid': '$courseId', 'userid': '$userId'},
    ) as Map<String, dynamic>;

    final usergrades = (data['usergrades'] as List?) ?? [];
    if (usergrades.isEmpty) return [];
    final items = ((usergrades[0] as Map)['gradeitems'] as List?) ?? [];
    return items
        .map((e) => MoodleGradeItem.fromJson(e as Map<String, dynamic>))
        .where((item) => item.isSubmittable)
        .toList();
  }

  Future<List<MoodleStudent>> getStudents({
    required String baseUrl,
    required String token,
    required int courseId,
  }) async {
    final data = await _ws(
      baseUrl,
      token,
      'core_enrol_get_enrolled_users',
      {'courseid': '$courseId'},
    ) as List<dynamic>;
    return data
        .map((e) => MoodleStudent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Submits a grade for [item] to student [studentId].
  ///
  /// Strategy by item type:
  /// 1. mod_assign  → [mod_assign_save_grade]  (included in moodle_mobile_app)
  /// 2. other mod   → [core_grades_update_grades] with component='mod_X'
  /// 3. manual      → tries [gradeimport_direct_import_grades] first,
  ///                   then falls back to [core_grades_update_grades] with
  ///                   component='manual'; both require a custom WS service.
  Future<void> submitGrade({
    required String baseUrl,
    required String token,
    required int courseId,
    required MoodleGradeItem item,
    required int studentId,
    required double grade,
  }) async {
    if (item.itemType == 'mod' && item.itemModule == 'assign') {
      await _submitViaAssign(baseUrl, token, item, studentId, grade);
    } else if (item.itemType == 'mod') {
      await _submitViaGradeUpdate(baseUrl, token, courseId, item, studentId, grade);
    } else {
      // Manual item: try direct import first, then grade_update fallback.
      await _submitManualItem(baseUrl, token, courseId, item, studentId, grade);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Strategy implementations
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _submitViaAssign(
    String baseUrl,
    String token,
    MoodleGradeItem item,
    int studentId,
    double grade,
  ) async {
    await _ws(baseUrl, token, 'mod_assign_save_grade', {
      'assignmentid': '${item.itemInstance}',
      'userid': '$studentId',
      'grade': grade.toStringAsFixed(2),
      'attemptnumber': '-1',
      'addattempt': '0',
      'workflowstate': 'graded',
      'applytoall': '0',
      'plugindata[assignfeedbackcomments_editor][text]': '',
      'plugindata[assignfeedbackcomments_editor][format]': '1',
    });
  }

  Future<void> _submitViaGradeUpdate(
    String baseUrl,
    String token,
    int courseId,
    MoodleGradeItem item,
    int studentId,
    double grade,
  ) async {
    await _ws(baseUrl, token, 'core_grades_update_grades', {
      'source': 'corrigirProva',
      'courseid': '$courseId',
      'component': 'mod_${item.itemModule}',
      'activityid': '${item.itemInstance ?? 0}',
      'itemnumber': '${item.itemNumber}',
      'grades[0][studentid]': '$studentId',
      'grades[0][grade]': grade.toStringAsFixed(2),
    });
  }

  /// Manual grade items cannot be updated via [grade_update()] because they
  /// have no component in Moodle. Strategy:
  ///   1. Try [gradeimport_direct_import_grades] — uses the item's numeric ID
  ///      directly and works for any item type. Requires the plugin to be
  ///      enabled and the WS function in the service.
  ///   2. Fallback: [core_grades_update_grades] with component='manual' —
  ///      may work on some Moodle configurations.
  ///
  /// Both strategies require a custom WS service. If both fail the error
  /// message contains actionable guidance.
  Future<void> _submitManualItem(
    String baseUrl,
    String token,
    int courseId,
    MoodleGradeItem item,
    int studentId,
    double grade,
  ) async {
    // Strategy 1: gradeimport_direct_import_grades
    try {
      await _ws(baseUrl, token, 'gradeimport_direct_import_grades', {
        'courseid': '$courseId',
        'data[0][gradeitem]': '${item.id}',
        'data[0][importcode]': 'corrigirProva_${DateTime.now().millisecondsSinceEpoch}',
        'data[0][grades][0][userid]': '$studentId',
        'data[0][grades][0][grade]': grade.toStringAsFixed(2),
        'data[0][grades][0][feedback]': '',
      });
      return; // success
    } on MoodleException catch (e) {
      // If it's a "not in service" or "function not found" error, try fallback.
      final code = e.errorCode ?? '';
      if (!_isServiceError(code)) rethrow; // unexpected error — propagate
    }

    // Strategy 2: core_grades_update_grades with component='manual'
    await _ws(baseUrl, token, 'core_grades_update_grades', {
      'source': 'corrigirProva',
      'courseid': '$courseId',
      'component': 'manual',
      'activityid': '0',
      'itemnumber': '${item.itemNumber}',
      'grades[0][studentid]': '$studentId',
      'grades[0][grade]': grade.toStringAsFixed(2),
    });
  }

  /// Returns true when the error code indicates the WS function is not
  /// available in the current service (not a business-logic error).
  bool _isServiceError(String code) =>
      code == 'accessdenied' ||
      code == 'webserviceaccessexception' ||
      code == 'servicenotavailable' ||
      code == 'invalidfunction';

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  Uri _uri(String baseUrl, String path) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse('$base$path');
  }

  void _checkStatus(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw MoodleException('Erro HTTP ${resp.statusCode}');
    }
  }

  dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      throw const MoodleException('Resposta inválida do servidor.');
    }
  }

  Future<dynamic> _ws(
    String baseUrl,
    String token,
    String function, [
    Map<String, String> extra = const {},
  ]) async {
    final resp = await http.post(
      _uri(baseUrl, 'webservice/rest/server.php'),
      body: {
        'wstoken': token,
        'moodlewsrestformat': 'json',
        'wsfunction': function,
        ...extra,
      },
    );
    _checkStatus(resp);
    final decoded = _decode(resp.body);
    if (decoded is Map && decoded.containsKey('exception')) {
      final errorCode = decoded['errorcode'] as String?;
      final message = (decoded['message'] as String?) ??
          decoded['exception'].toString();
      throw MoodleException(_friendlyMessage(message, errorCode),
          errorCode: errorCode);
    }
    return decoded;
  }

  /// Turns Moodle machine error codes into actionable Portuguese messages.
  String _friendlyMessage(String original, String? errorCode) {
    switch (errorCode) {
      case 'accessdenied':
      case 'webserviceaccessexception':
        return 'Função não autorizada no serviço Moodle.\n'
            'Crie um Serviço Externo personalizado em:\n'
            'Admin → Servidor → Web services → Serviços externos\n'
            'e adicione: core_grades_update_grades, '
            'mod_assign_save_grade, gradeimport_direct_import_grades.\n'
            'Use o token deste serviço ao conectar.';
      case 'nopermissions':
        return 'Sem permissão para editar notas neste curso.\n'
            'Verifique se você tem o papel de Professor com edição.';
      case 'servicenotavailable':
        return 'Serviço "$original" não encontrado no Moodle.\n'
            'Verifique o nome do serviço nas configurações avançadas.';
      default:
        return original;
    }
  }
}
