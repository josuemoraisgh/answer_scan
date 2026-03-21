import 'answer_option.dart';
import 'answer_sheet.dart';

class OmrScanResult {
  const OmrScanResult({
    required this.success,
    required this.sheetStatus,
    required this.rawAnswers,
    required this.confidence,
    required this.scores,
    required this.markersDetected,
    required this.perspectiveCorrected,
    this.debugImagePath,
    this.error,
  });

  final bool success;
  final String sheetStatus;
  final Map<String, String> rawAnswers;
  final Map<String, double> confidence;
  final Map<String, List<double>> scores;
  final int markersDetected;
  final bool perspectiveCorrected;
  final String? debugImagePath;
  final String? error;

  AnswerSheet toAnswerSheet() {
    final answers = List<AnswerOption?>.generate(AnswerSheet.totalQuestions, (
      index,
    ) {
      final raw = rawAnswers['${index + 1}'];
      return _parseOption(raw);
    });

    return AnswerSheet(answers);
  }

  bool get requiresReview =>
      reviewQuestionNumbers.isNotEmpty || sheetStatus == 'review_required';

  int get unresolvedCount => reviewQuestionNumbers.length;

  int get resolvedCount =>
      rawAnswers.values.where(_isResolvedAnswerLabel).length;

  double get averageConfidence {
    if (confidence.isEmpty) {
      return 0;
    }

    final total = confidence.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    return total / confidence.length;
  }

  List<int> get reviewQuestionNumbers {
    final questions = <int>[];

    for (final entry in rawAnswers.entries) {
      if (!_isResolvedAnswerLabel(entry.value)) {
        final question = int.tryParse(entry.key);
        if (question != null) {
          questions.add(question);
        }
      }
    }

    questions.sort();
    return questions;
  }

  String get summary {
    if (!success) {
      return error ?? 'Scan failed';
    }

    final buffer = StringBuffer();
    for (var question = 1; question <= AnswerSheet.totalQuestions; question++) {
      final answer = rawAnswers['$question'] ?? '?';
      buffer.write('$question:$answer');
      if (question < AnswerSheet.totalQuestions) {
        buffer.write('  ');
      }
    }
    return buffer.toString();
  }

  static OmrScanResult fromMap(Map<Object?, Object?> raw) {
    final success = raw['success'] as bool? ?? false;
    final debug = raw['debug'] as Map<Object?, Object?>? ?? {};

    if (!success) {
      return OmrScanResult(
        success: false,
        sheetStatus: raw['sheetStatus']?.toString() ?? 'error',
        rawAnswers: const {},
        confidence: const {},
        scores: const {},
        markersDetected: (debug['markersDetected'] as int?) ?? 0,
        perspectiveCorrected: (debug['perspectiveCorrected'] as bool?) ?? false,
        error: raw['error'] as String? ?? 'Unknown error',
      );
    }

    return OmrScanResult(
      success: true,
      sheetStatus: raw['sheetStatus']?.toString() ?? 'ok',
      rawAnswers: _parseStringMap(raw['answers']),
      confidence: _parseDoubleMap(raw['confidence']),
      scores: _parseScoresMap(raw['scores']),
      markersDetected: (debug['markersDetected'] as int?) ?? 0,
      perspectiveCorrected: (debug['perspectiveCorrected'] as bool?) ?? false,
      debugImagePath: raw['debugImagePath'] as String?,
    );
  }

  static Map<String, String> _parseStringMap(Object? raw) {
    if (raw == null) {
      return const {};
    }

    return (raw as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }

  static Map<String, double> _parseDoubleMap(Object? raw) {
    if (raw == null) {
      return const {};
    }

    return (raw as Map<Object?, Object?>).map(
      (key, value) =>
          MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0),
    );
  }

  static Map<String, List<double>> _parseScoresMap(Object? raw) {
    if (raw == null) {
      return const {};
    }

    return (raw as Map<Object?, Object?>).map((key, value) {
      final parsedList = (value as List<dynamic>? ?? const [])
          .map((item) => (item as num).toDouble())
          .toList(growable: false);
      return MapEntry(key.toString(), parsedList);
    });
  }

  static AnswerOption? _parseOption(String? label) {
    switch (label) {
      case 'A':
        return AnswerOption.a;
      case 'B':
        return AnswerOption.b;
      case 'C':
        return AnswerOption.c;
      case 'D':
        return AnswerOption.d;
      case 'E':
        return AnswerOption.e;
      default:
        return null;
    }
  }

  static bool _isResolvedAnswerLabel(String label) {
    switch (label) {
      case 'A':
      case 'B':
      case 'C':
      case 'D':
      case 'E':
        return true;
      default:
        return false;
    }
  }
}
