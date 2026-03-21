import 'package:flutter/services.dart';

import '../../domain/entities/answer_option.dart';
import '../../domain/entities/answer_sheet.dart';

/// Flutter client for the native Kotlin/OpenCV OMR scanner.
///
/// Sends an image file path to Android via MethodChannel and receives:
///   - 20 answer strings ("A"–"E", "BLANK", "MULTIPLE", "AMBIGUOUS")
///   - 20×5 raw density scores
///   - 4 inner-corner pixel coordinates (for debug / calibration)
///   - Optional path to a debug JPEG
class OmrNativeChannel {
  static const _channel = MethodChannel('com.example.answer_scan/omr');

  /// Scans [imagePath] and returns a parsed [AnswerSheet].
  ///
  /// Throws [PlatformException] when the native side reports an error.
  static Future<AnswerSheet> scan(String imagePath, {bool debug = false}) async {
    final Map<Object?, Object?> raw = await _channel.invokeMethod(
      'scanSheet',
      {'imagePath': imagePath, 'debug': debug},
    );

    final answers = (raw['answers'] as List)
        .map((s) => _parseOption(s as String))
        .toList();

    return AnswerSheet(answers);
  }

  /// Scans and also returns the full raw result (scores, corners, debugPath).
  static Future<OmrNativeResult> scanWithDebug(String imagePath) async {
    final Map<Object?, Object?> raw = await _channel.invokeMethod(
      'scanSheet',
      {'imagePath': imagePath, 'debug': true},
    );

    final rawAnswers = raw['answers'] as List;
    final rawScores  = raw['scores']  as List;

    final answers = rawAnswers
        .map((s) => _parseOption(s as String))
        .toList();

    final scores = rawScores
        .map((col) => (col as List).map((v) => (v as num).toDouble()).toList())
        .toList();

    final corners = (raw['innerCorners'] as List)
        .map((pt) => (pt as List).map((v) => (v as num).toDouble()).toList())
        .toList();

    return OmrNativeResult(
      sheet:          AnswerSheet(answers),
      rawAnswers:     rawAnswers.cast<String>(),
      scores:         scores,
      innerCorners:   corners,
      debugImagePath: raw['debugImagePath'] as String?,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Maps the native string label to [AnswerOption?].
  /// "BLANK", "MULTIPLE", and "AMBIGUOUS" all map to null (no clear answer).
  static AnswerOption? _parseOption(String label) {
    switch (label) {
      case 'A': return AnswerOption.a;
      case 'B': return AnswerOption.b;
      case 'C': return AnswerOption.c;
      case 'D': return AnswerOption.d;
      case 'E': return AnswerOption.e;
      default:  return null; // BLANK | MULTIPLE | AMBIGUOUS
    }
  }
}

/// Extended result returned by [OmrNativeChannel.scanWithDebug].
class OmrNativeResult {
  const OmrNativeResult({
    required this.sheet,
    required this.rawAnswers,
    required this.scores,
    required this.innerCorners,
    this.debugImagePath,
  });

  /// Parsed answer sheet (nulls for blank / ambiguous / multiple).
  final AnswerSheet sheet;

  /// Raw 20-element list: "A"–"E", "BLANK", "MULTIPLE", "AMBIGUOUS".
  final List<String> rawAnswers;

  /// 20 × 5 dark-pixel density scores in [0, 1].
  final List<List<double>> scores;

  /// [[x,y]×4] grid inner-corner coordinates (TL, TR, BL, BR).
  final List<List<double>> innerCorners;

  /// Path to debug JPEG (null when not requested or not produced).
  final String? debugImagePath;
}
