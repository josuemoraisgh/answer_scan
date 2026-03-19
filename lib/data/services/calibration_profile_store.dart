import 'package:shared_preferences/shared_preferences.dart';

import 'omr_sheet_scanner.dart';

class CalibrationProfileStore {
  static const _thresholdBiasKey = 'calibration.thresholdBias';
  static const _minInkScoreKey = 'calibration.minInkScore';
  static const _minGapKey = 'calibration.minGap';
  static const _minMeanOffsetKey = 'calibration.minMeanOffset';
  static const _cellInsetKey = 'calibration.cellInset';

  Future<OMRScannerCalibration> load() async {
    final prefs = await SharedPreferences.getInstance();

    return OMRScannerCalibration(
      thresholdBias: prefs.getDouble(_thresholdBiasKey) ?? 0,
      minInkScore: prefs.getDouble(_minInkScoreKey) ?? 0.08,
      minGap: prefs.getDouble(_minGapKey) ?? 0.03,
      minMeanOffset: prefs.getDouble(_minMeanOffsetKey) ?? 0.02,
      cellInset: prefs.getDouble(_cellInsetKey) ?? 0.28,
    );
  }

  Future<void> save(OMRScannerCalibration calibration) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble(_thresholdBiasKey, calibration.thresholdBias);
    await prefs.setDouble(_minInkScoreKey, calibration.minInkScore);
    await prefs.setDouble(_minGapKey, calibration.minGap);
    await prefs.setDouble(_minMeanOffsetKey, calibration.minMeanOffset);
    await prefs.setDouble(_cellInsetKey, calibration.cellInset);
  }
}
