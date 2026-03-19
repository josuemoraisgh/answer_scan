import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../../core/omr_capture_guide.dart';
import '../../domain/entities/answer_option.dart';
import '../../domain/entities/answer_sheet.dart';

class OMRScannerCalibration {
  const OMRScannerCalibration({
    this.thresholdBias = 0,
    this.minInkScore = 0.18,
    this.minGap = 0.08,
    this.minMeanOffset = 0.02,
    this.cellInset = 0.25,
  });

  final double thresholdBias;
  final double minInkScore;
  final double minGap;
  final double minMeanOffset;
  final double cellInset;

  OMRScannerCalibration copyWith({
    double? thresholdBias,
    double? minInkScore,
    double? minGap,
    double? minMeanOffset,
    double? cellInset,
  }) {
    return OMRScannerCalibration(
      thresholdBias: thresholdBias ?? this.thresholdBias,
      minInkScore: minInkScore ?? this.minInkScore,
      minGap: minGap ?? this.minGap,
      minMeanOffset: minMeanOffset ?? this.minMeanOffset,
      cellInset: cellInset ?? this.cellInset,
    );
  }
}

class OMRQuestionDebugResult {
  const OMRQuestionDebugResult({
    required this.questionNumber,
    required this.optionScores,
    required this.marked,
  });

  final int questionNumber;
  final List<double> optionScores;
  final AnswerOption? marked;

  double get bestScore => optionScores.reduce(max);

  double get secondBestScore {
    final sorted = [...optionScores]..sort((a, b) => b.compareTo(a));
    return sorted.length > 1 ? sorted[1] : sorted[0];
  }

  double get scoreGap => bestScore - secondBestScore;
}

class OMRDebugPoint {
  const OMRDebugPoint({required this.x, required this.y});

  final double x;
  final double y;
}

class OMRDebugRect {
  const OMRDebugRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

class OMRDebugGeometry {
  const OMRDebugGeometry({
    required this.guideRect,
    required this.contentRect,
    required this.topLeftMarker,
    required this.topRightMarker,
    required this.bottomLeftMarker,
    required this.bottomRightMarker,
    required this.gridTopLeft,
    required this.gridTopRight,
    required this.gridBottomLeft,
    required this.gridBottomRight,
  });

  final OMRDebugRect guideRect;
  final OMRDebugRect contentRect;
  final OMRDebugRect topLeftMarker;
  final OMRDebugRect topRightMarker;
  final OMRDebugRect bottomLeftMarker;
  final OMRDebugRect bottomRightMarker;
  final OMRDebugPoint gridTopLeft;
  final OMRDebugPoint gridTopRight;
  final OMRDebugPoint gridBottomLeft;
  final OMRDebugPoint gridBottomRight;
}

class OMRLiveAnswerCell {
  const OMRLiveAnswerCell({
    required this.questionIndex,
    required this.optionIndex,
    required this.rect,
  });

  final int questionIndex;
  final int optionIndex;
  final OMRDebugRect rect;
}

class OMRLiveGuideDebug {
  const OMRLiveGuideDebug({
    required this.contentRect,
    required this.topLeftMarker,
    required this.topRightMarker,
    required this.bottomLeftMarker,
    required this.bottomRightMarker,
    this.detectedAnswers = const [],
  });

  final OMRDebugRect contentRect;
  final OMRDebugRect topLeftMarker;
  final OMRDebugRect topRightMarker;
  final OMRDebugRect bottomLeftMarker;
  final OMRDebugRect bottomRightMarker;
  final List<OMRLiveAnswerCell> detectedAnswers;
}

class OMRScanDebugResult {
  const OMRScanDebugResult({
    required this.sheet,
    required this.threshold,
    required this.questions,
    required this.geometry,
    required this.imageAspectRatio,
  });

  final AnswerSheet sheet;
  final double threshold;
  final List<OMRQuestionDebugResult> questions;
  final OMRDebugGeometry geometry;
  final double imageAspectRatio;
}

class OMRSheetScanner {
  OMRSheetScanner({
    OMRScannerCalibration defaultCalibration = const OMRScannerCalibration(),
  }) : _defaultCalibration = defaultCalibration;

  OMRScannerCalibration _defaultCalibration;

  OMRScannerCalibration get defaultCalibration => _defaultCalibration;

  void setDefaultCalibration(OMRScannerCalibration calibration) {
    _defaultCalibration = calibration;
  }

  Future<AnswerSheet> scan(
    String imagePath, {
    OMRScannerCalibration? calibration,
  }) async {
    final debug = await scanWithDebug(imagePath, calibration: calibration);
    return debug.sheet;
  }

  OMRLiveGuideDebug detectLiveGuide({
    required Uint8List luminanceBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    bool isLandscape = false,
  }) {
    final sourceGray = _GrayImage.fromLumaPlane(
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
      luminanceBytes: luminanceBytes,
    );

    // Normalize size for consistent processing
    final normalized = _normalizeGrayImageSize(sourceGray);

    // Camera sensor always outputs landscape frames.
    // In portrait mode, rotate to match what the user sees.
    // In landscape mode, the frame already matches.
    var gray = normalized;
    if (!isLandscape && gray.width > gray.height) {
      gray = gray.rotate90Clockwise();
    }

    final guideCrop = _computeGuideCrop(gray.width, gray.height);
    final guidedGray = gray.crop(
      x: guideCrop.x,
      y: guideCrop.y,
      width: guideCrop.width,
      height: guideCrop.height,
    );

    final markers = _findCornerMarkers(guidedGray);
    final grid = _buildGridFrame(markers);

    final allScores = _computeAllCellScores(
      gray: guidedGray,
      grid: grid,
      inset: _defaultCalibration.cellInset,
      cellRes: 14,
    );

    final detectedAnswers = <OMRLiveAnswerCell>[];
    final guideW = guidedGray.width.toDouble();
    final guideH = guidedGray.height.toDouble();

    for (var q = 0; q < AnswerSheet.totalQuestions; q++) {
      final scores = allScores[q];

      final marked = _pickMarkedOption(scores, _defaultCalibration);
      if (marked != null) {
        final col = q / _gridCols;
        final colEnd = (q + 1) / _gridCols;
        final row = marked.index / _gridRows;
        final rowEnd = (marked.index + 1) / _gridRows;

        final tl = _mapFromGrid(col, row, grid);
        final br = _mapFromGrid(colEnd, rowEnd, grid);

        detectedAnswers.add(
          OMRLiveAnswerCell(
            questionIndex: q,
            optionIndex: marked.index,
            rect: OMRDebugRect(
              left: min(tl.dx, br.dx) / guideW,
              top: min(tl.dy, br.dy) / guideH,
              right: max(tl.dx, br.dx) / guideW,
              bottom: max(tl.dy, br.dy) / guideH,
            ),
          ),
        );
      }
    }

    return OMRLiveGuideDebug(
      contentRect: _normalizeContentBoundsToGuide(
        guideWidth: guidedGray.width,
        guideHeight: guidedGray.height,
        rect: markers.contentBounds,
      ),
      topLeftMarker: _normalizeMarkerBoxToGuide(
        guideWidth: guidedGray.width,
        guideHeight: guidedGray.height,
        rect: markers.topLeft,
      ),
      topRightMarker: _normalizeMarkerBoxToGuide(
        guideWidth: guidedGray.width,
        guideHeight: guidedGray.height,
        rect: markers.topRight,
      ),
      bottomLeftMarker: _normalizeMarkerBoxToGuide(
        guideWidth: guidedGray.width,
        guideHeight: guidedGray.height,
        rect: markers.bottomLeft,
      ),
      bottomRightMarker: _normalizeMarkerBoxToGuide(
        guideWidth: guidedGray.width,
        guideHeight: guidedGray.height,
        rect: markers.bottomRight,
      ),
      detectedAnswers: detectedAnswers,
    );
  }

  Future<OMRScanDebugResult> scanWithDebug(
    String imagePath, {
    OMRScannerCalibration? calibration,
  }) async {
    final effectiveCalibration = calibration ?? _defaultCalibration;

    final bytes = await File(imagePath).readAsBytes();
    final decodedImage = _decode(bytes);

    // Normalize size for consistent processing
    var gray = _GrayImage.fromImage(decodedImage);
    gray = _normalizeGrayImageSize(gray);

    // Photo orientation is handled by EXIF in img.decodeImage.
    // The guide crop produces a landscape-shaped region in both orientations.

    final guideCrop = _computeGuideCrop(gray.width, gray.height);
    final guidedGray = gray.crop(
      x: guideCrop.x,
      y: guideCrop.y,
      width: guideCrop.width,
      height: guideCrop.height,
    );

    final markers = _findCornerMarkers(guidedGray);
    final grid = _buildGridFrame(markers);
    final threshold =
        (_computeOtsuThreshold(guidedGray, grid) +
                effectiveCalibration.thresholdBias)
            .clamp(45, 200)
            .toDouble();

    final allScores = _computeAllCellScores(
      gray: guidedGray,
      grid: grid,
      inset: effectiveCalibration.cellInset,
      cellRes: 24,
    );

    final debugQuestions = <OMRQuestionDebugResult>[];

    for (var question = 0; question < AnswerSheet.totalQuestions; question++) {
      final scores = allScores[question];

      final marked = _pickMarkedOption(scores, effectiveCalibration);
      debugQuestions.add(
        OMRQuestionDebugResult(
          questionNumber: question + 1,
          optionScores: List<double>.unmodifiable(scores),
          marked: marked,
        ),
      );
    }

    final answers = debugQuestions.map((q) => q.marked).toList();
    final geometry = _buildDebugGeometry(
      guideCrop: guideCrop,
      guideWidth: guidedGray.width,
      guideHeight: guidedGray.height,
      markers: markers,
      grid: grid,
    );

    return OMRScanDebugResult(
      sheet: AnswerSheet(answers),
      threshold: threshold,
      questions: List<OMRQuestionDebugResult>.unmodifiable(debugQuestions),
      geometry: geometry,
      imageAspectRatio: decodedImage.width / decodedImage.height,
    );
  }

  img.Image _decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Nao foi possivel decodificar a imagem.');
    }
    return decoded;
  }

  /// Normalize gray image size to ~1200px width for consistent processing
  _GrayImage _normalizeGrayImageSize(_GrayImage gray) {
    const targetWidth = 1200;
    if (gray.width > targetWidth) {
      final scale = targetWidth / gray.width;
      final newHeight = (gray.height * scale).round();
      return _resizeGrayImage(gray, targetWidth, newHeight);
    }
    return gray;
  }

  /// Resize a grayscale image using bilinear interpolation
  _GrayImage _resizeGrayImage(_GrayImage source, int newWidth, int newHeight) {
    final pixels = List<double>.filled(newWidth * newHeight, 0);

    for (var y = 0; y < newHeight; y++) {
      for (var x = 0; x < newWidth; x++) {
        final srcX = x * source.width / newWidth;
        final srcY = y * source.height / newHeight;

        // Bilinear interpolation
        final x0 = srcX.floor();
        final x1 = (x0 + 1).clamp(0, source.width - 1);
        final y0 = srcY.floor();
        final y1 = (y0 + 1).clamp(0, source.height - 1);

        final fx = srcX - x0;
        final fy = srcY - y0;

        final v00 = source.at(x0, y0);
        final v10 = source.at(x1, y0);
        final v01 = source.at(x0, y1);
        final v11 = source.at(x1, y1);

        final v0 = v00 * (1 - fx) + v10 * fx;
        final v1 = v01 * (1 - fx) + v11 * fx;
        final value = v0 * (1 - fy) + v1 * fy;

        pixels[y * newWidth + x] = value;
      }
    }

    return _GrayImage(newWidth, newHeight, pixels);
  }

  _GuideCrop _computeGuideCrop(int sourceWidth, int sourceHeight) {
    final cropWidth = (sourceWidth * OMRCaptureGuide.widthFactor).round();
    final cropHeight = (cropWidth * OMRCaptureGuide.heightFromWidthFactor)
        .round();

    final safeWidth = cropWidth.clamp(1, sourceWidth);
    final safeHeight = cropHeight.clamp(1, sourceHeight);

    final offsetX = ((sourceWidth - safeWidth) / 2).round().clamp(
      0,
      sourceWidth - safeWidth,
    );
    final offsetY = ((sourceHeight - safeHeight) / 2).round().clamp(
      0,
      sourceHeight - safeHeight,
    );

    return _GuideCrop(
      x: offsetX,
      y: offsetY,
      width: safeWidth,
      height: safeHeight,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  _CornerMarkers _findCornerMarkers(_GrayImage gray) {
    final w = gray.width;
    final h = gray.height;

    // Step 1: Compute Otsu threshold to separate dark from light
    final otsu = _computeImageOtsuThreshold(gray);
    final darkThreshold = min(otsu * 0.85, 130.0);

    // Step 2: Build integral image for fast rectangular density queries
    final integral = _buildDarkIntegral(gray, darkThreshold);

    // Step 3: Estimate marker size range based on image dimensions
    final minSide = max(6, (w * 0.012).round());
    final maxSide = max(20, (w * 0.06).round());

    // Step 4: Search in generous quadrants (45% from each corner)
    final qw = (w * 0.45).round();
    final qh = (h * 0.45).round();

    // Collect ALL dense candidates from the entire image once
    final allCandidates = _collectDenseCandidates(
      integral,
      w,
      h,
      0,
      0,
      w,
      h,
      minSide,
      maxSide,
    );

    // Step 5: For each corner, pick the candidate closest to that corner
    // Corner markers are always the extreme-most dense blocks
    final topLeft = _pickCornerCandidate(
      allCandidates,
      gray,
      darkThreshold,
      integral,
      w,
      h,
      0,
      0,
      qw,
      qh, // search region
      0.0,
      0.0, // corner target (top-left of image)
    );
    final topRight = _pickCornerCandidate(
      allCandidates,
      gray,
      darkThreshold,
      integral,
      w,
      h,
      w - qw,
      0,
      w,
      qh,
      w.toDouble(),
      0.0, // corner target (top-right of image)
    );
    final bottomLeft = _pickCornerCandidate(
      allCandidates,
      gray,
      darkThreshold,
      integral,
      w,
      h,
      0,
      h - qh,
      qw,
      h,
      0.0,
      h.toDouble(), // corner target (bottom-left of image)
    );
    final bottomRight = _pickCornerCandidate(
      allCandidates,
      gray,
      darkThreshold,
      integral,
      w,
      h,
      w - qw,
      h - qh,
      w,
      h,
      w.toDouble(),
      h.toDouble(), // corner target (bottom-right of image)
    );

    final contentBounds = _ContentBounds(
      left: min(topLeft.left, bottomLeft.left),
      right: max(topRight.right, bottomRight.right),
      top: min(topLeft.top, topRight.top),
      bottom: max(bottomLeft.bottom, bottomRight.bottom),
    );

    return _CornerMarkers(
      topLeft: topLeft,
      topRight: topRight,
      bottomLeft: bottomLeft,
      bottomRight: bottomRight,
      contentBounds: contentBounds,
    );
  }

  /// Collect all dense block candidates from a search region.
  List<_BlockCandidate> _collectDenseCandidates(
    List<int> integral,
    int imgW,
    int imgH,
    int searchX1,
    int searchY1,
    int searchX2,
    int searchY2,
    int minSide,
    int maxSide,
  ) {
    final candidates = <_BlockCandidate>[];
    final numSizes = 8;
    final sizeStep = max(1, (maxSide - minSide) ~/ numSizes);

    for (var size = minSide; size <= maxSide; size += sizeStep) {
      final step = max(1, size ~/ 4);
      for (var y = searchY1; y + size <= searchY2; y += step) {
        for (var x = searchX1; x + size <= searchX2; x += step) {
          final count = _integralRectSum(
            integral,
            imgW,
            x,
            y,
            x + size,
            y + size,
          );
          final density = count / (size * size);
          if (density > 0.30) {
            candidates.add(
              _BlockCandidate(x: x, y: y, size: size, density: density),
            );
          }
        }
      }
    }

    return candidates;
  }

  /// Pick the best candidate for a specific corner.
  /// Prioritizes candidates closest to the corner of the image.
  _MarkerBox _pickCornerCandidate(
    List<_BlockCandidate> allCandidates,
    _GrayImage gray,
    double threshold,
    List<int> integral,
    int imgW,
    int imgH,
    int regionX1,
    int regionY1,
    int regionX2,
    int regionY2,
    double cornerX,
    double cornerY,
  ) {
    // Filter candidates that fall within this corner's search region
    final regional = allCandidates.where((c) {
      final cx = c.x + c.size / 2;
      final cy = c.y + c.size / 2;
      return cx >= regionX1 &&
          cx <= regionX2 &&
          cy >= regionY1 &&
          cy <= regionY2;
    }).toList();

    if (regional.isEmpty) {
      throw const FormatException(
        'Nao foi possivel localizar os 4 marcadores. '
        'Tente aproximar e alinhar melhor a folha.',
      );
    }

    // Compute max distance for normalization (diagonal of search region)
    final regionW = (regionX2 - regionX1).toDouble();
    final regionH = (regionY2 - regionY1).toDouble();
    final maxDist = sqrt(regionW * regionW + regionH * regionH);

    _BlockCandidate? best;
    var bestScore = double.negativeInfinity;

    for (final c in regional) {
      final cx = c.x + c.size / 2;
      final cy = c.y + c.size / 2;
      final dx = cx - cornerX;
      final dy = cy - cornerY;
      final dist = sqrt(dx * dx + dy * dy);

      // Proximity: 1.0 when at the corner, 0.0 when at max distance
      final proximity = 1.0 - (dist / maxDist).clamp(0.0, 1.0);

      // Score heavily favors proximity to the corner (70%)
      // with density as a secondary filter (30%)
      final score = proximity * 0.70 + c.density * 0.30;

      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }

    if (best == null) {
      throw const FormatException(
        'Nao foi possivel localizar os 4 marcadores. '
        'Tente aproximar e alinhar melhor a folha.',
      );
    }

    return _refineMarkerBounds(
      gray,
      best.x,
      best.y,
      best.x + best.size - 1,
      best.y + best.size - 1,
      threshold,
    );
  }

  /// Compute Otsu threshold on the full image for binarization.
  double _computeImageOtsuThreshold(_GrayImage gray) {
    final histogram = List<int>.filled(256, 0);
    var total = 0;

    // Sample every 2nd pixel for speed
    for (var y = 0; y < gray.height; y += 2) {
      for (var x = 0; x < gray.width; x += 2) {
        histogram[gray.at(x, y).round().clamp(0, 255)]++;
        total++;
      }
    }

    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    var sumBg = 0.0;
    var wBg = 0;
    var maxVariance = 0.0;
    var threshold = 120;

    for (var i = 0; i < 256; i++) {
      wBg += histogram[i];
      if (wBg == 0) continue;
      final wFg = total - wBg;
      if (wFg == 0) break;

      sumBg += i * histogram[i];
      final meanBg = sumBg / wBg;
      final meanFg = (sum - sumBg) / wFg;

      final variance = wBg * wFg * pow(meanBg - meanFg, 2);
      if (variance > maxVariance) {
        maxVariance = variance.toDouble();
        threshold = i;
      }
    }

    return threshold.clamp(60, 180).toDouble();
  }

  /// Build integral image where each cell = count of dark pixels in [0,0]..[x,y].
  List<int> _buildDarkIntegral(_GrayImage gray, double threshold) {
    final w = gray.width;
    final h = gray.height;
    final integral = List<int>.filled(w * h, 0);

    for (var y = 0; y < h; y++) {
      var rowSum = 0;
      for (var x = 0; x < w; x++) {
        rowSum += gray.at(x, y) <= threshold ? 1 : 0;
        integral[y * w + x] = rowSum + (y > 0 ? integral[(y - 1) * w + x] : 0);
      }
    }

    return integral;
  }

  /// Query the integral image for the sum of dark pixels in a rectangle.
  /// Rectangle is [x1, y1] inclusive to [x2, y2] exclusive.
  int _integralRectSum(
    List<int> integral,
    int imgW,
    int x1,
    int y1,
    int x2,
    int y2,
  ) {
    final ix2 = x2 - 1;
    final iy2 = y2 - 1;
    if (ix2 < 0 || iy2 < 0) return 0;

    final a = integral[iy2 * imgW + ix2];
    final b = y1 > 0 ? integral[(y1 - 1) * imgW + ix2] : 0;
    final c = x1 > 0 ? integral[iy2 * imgW + (x1 - 1)] : 0;
    final d = (x1 > 0 && y1 > 0) ? integral[(y1 - 1) * imgW + (x1 - 1)] : 0;

    return a - b - c + d;
  }

  /// Tighten marker bounds by trimming columns/rows with low dark-pixel density.
  _MarkerBox _refineMarkerBounds(
    _GrayImage gray,
    int rawLeft,
    int rawTop,
    int rawRight,
    int rawBottom,
    double threshold,
  ) {
    // Expand slightly to catch edges the coarse scan might have clipped
    final expand = max(2, ((rawRight - rawLeft) * 0.25).round());
    var left = max(0, rawLeft - expand);
    var right = min(gray.width - 1, rawRight + expand);
    var top = max(0, rawTop - expand);
    var bottom = min(gray.height - 1, rawBottom + expand);

    const minDensity = 0.25;

    // Trim left
    while (left < right) {
      var dark = 0;
      for (var y = top; y <= bottom; y++) {
        if (gray.at(left, y) <= threshold) dark++;
      }
      if (dark / (bottom - top + 1) >= minDensity) break;
      left++;
    }

    // Trim right
    while (right > left) {
      var dark = 0;
      for (var y = top; y <= bottom; y++) {
        if (gray.at(right, y) <= threshold) dark++;
      }
      if (dark / (bottom - top + 1) >= minDensity) break;
      right--;
    }

    // Trim top
    while (top < bottom) {
      var dark = 0;
      for (var x = left; x <= right; x++) {
        if (gray.at(x, top) <= threshold) dark++;
      }
      if (dark / (right - left + 1) >= minDensity) break;
      top++;
    }

    // Trim bottom
    while (bottom > top) {
      var dark = 0;
      for (var x = left; x <= right; x++) {
        if (gray.at(x, bottom) <= threshold) dark++;
      }
      if (dark / (right - left + 1) >= minDensity) break;
      bottom--;
    }

    // Compute actual dark pixel count in refined box
    var area = 0;
    for (var y = top; y <= bottom; y++) {
      for (var x = left; x <= right; x++) {
        if (gray.at(x, y) <= threshold) area++;
      }
    }

    return _MarkerBox(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      area: area,
    );
  }

  OMRDebugGeometry _buildDebugGeometry({
    required _GuideCrop guideCrop,
    required int guideWidth,
    required int guideHeight,
    required _CornerMarkers markers,
    required _GridFrame grid,
  }) {
    return OMRDebugGeometry(
      guideRect: _normalizeContentBoundsToSource(
        guideCrop,
        _ContentBounds(left: 0, top: 0, right: guideWidth, bottom: guideHeight),
      ),
      contentRect: _normalizeContentBoundsToSource(
        guideCrop,
        markers.contentBounds,
      ),
      topLeftMarker: _normalizeMarkerBoxToSource(guideCrop, markers.topLeft),
      topRightMarker: _normalizeMarkerBoxToSource(guideCrop, markers.topRight),
      bottomLeftMarker: _normalizeMarkerBoxToSource(
        guideCrop,
        markers.bottomLeft,
      ),
      bottomRightMarker: _normalizeMarkerBoxToSource(
        guideCrop,
        markers.bottomRight,
      ),
      // Show the answer area (full grid between marker centers)
      gridTopLeft: _normalizePointToSource(guideCrop, _mapFromGrid(0, 0, grid)),
      gridTopRight: _normalizePointToSource(
        guideCrop,
        _mapFromGrid(1, 0, grid),
      ),
      gridBottomLeft: _normalizePointToSource(
        guideCrop,
        _mapFromGrid(0, 1, grid),
      ),
      gridBottomRight: _normalizePointToSource(
        guideCrop,
        _mapFromGrid(1, 1, grid),
      ),
    );
  }

  OMRDebugRect _normalizeContentBoundsToSource(
    _GuideCrop crop,
    _ContentBounds rect,
  ) {
    return OMRDebugRect(
      left: (crop.x + rect.left) / crop.sourceWidth,
      top: (crop.y + rect.top) / crop.sourceHeight,
      right: (crop.x + rect.right) / crop.sourceWidth,
      bottom: (crop.y + rect.bottom) / crop.sourceHeight,
    );
  }

  OMRDebugRect _normalizeMarkerBoxToSource(_GuideCrop crop, _MarkerBox rect) {
    return OMRDebugRect(
      left: (crop.x + rect.left) / crop.sourceWidth,
      top: (crop.y + rect.top) / crop.sourceHeight,
      right: (crop.x + rect.right) / crop.sourceWidth,
      bottom: (crop.y + rect.bottom) / crop.sourceHeight,
    );
  }

  OMRDebugRect _normalizeContentBoundsToGuide({
    required int guideWidth,
    required int guideHeight,
    required _ContentBounds rect,
  }) {
    return OMRDebugRect(
      left: rect.left / guideWidth,
      top: rect.top / guideHeight,
      right: rect.right / guideWidth,
      bottom: rect.bottom / guideHeight,
    );
  }

  OMRDebugRect _normalizeMarkerBoxToGuide({
    required int guideWidth,
    required int guideHeight,
    required _MarkerBox rect,
  }) {
    return OMRDebugRect(
      left: rect.left / guideWidth,
      top: rect.top / guideHeight,
      right: rect.right / guideWidth,
      bottom: rect.bottom / guideHeight,
    );
  }

  OMRDebugPoint _normalizePointToSource(_GuideCrop crop, Offset point) {
    return OMRDebugPoint(
      x: (crop.x + point.dx) / crop.sourceWidth,
      y: (crop.y + point.dy) / crop.sourceHeight,
    );
  }

  _GridFrame _buildGridFrame(_CornerMarkers markers) {
    // Use marker centers as the most robust and stable reference points.
    // The answer grid (20 cols × 5 rows) spans exactly between the
    // 4 marker center positions.
    final tl = markers.topLeft.center;
    final tr = markers.topRight.center;
    final bl = markers.bottomLeft.center;
    final br = markers.bottomRight.center;

    // Validate that the 4 markers form a proper convex quadrilateral.
    // Crossed or inverted markers would produce a degenerate grid.
    if (tl.dx >= tr.dx || bl.dx >= br.dx) {
      throw const FormatException(
        'Marcadores horizontais invertidos. Centralize a folha no guia.',
      );
    }
    if (tl.dy >= bl.dy || tr.dy >= br.dy) {
      throw const FormatException(
        'Marcadores verticais invertidos. Centralize a folha no guia.',
      );
    }

    return _GridFrame(
      topLeft: tl,
      topRight: tr,
      bottomLeft: bl,
      bottomRight: br,
    );
  }

  // The grid area between marker centers is exactly 20 columns × 5 rows
  // of answer cells. Bilinear interpolation from the 4 marker center points
  // maps [0,1] × [0,1] grid coordinates to pixel positions.
  static const _gridCols = 20;
  static const _gridRows = 5;

  double _computeOtsuThreshold(_GrayImage gray, _GridFrame grid) {
    final histogram = List<int>.filled(256, 0);
    var total = 0;

    // Sample the full grid area between marker centers
    const samples = 40;
    for (var row = 0; row < samples; row++) {
      final v = (row + 0.5) / samples;
      for (var col = 0; col < samples; col++) {
        final u = (col + 0.5) / samples;
        final point = _mapFromGrid(u, v, grid);
        final lum = gray.at(point.dx.round(), point.dy.round()).round();
        histogram[lum.clamp(0, 255)]++;
        total++;
      }
    }

    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    var sumBackground = 0.0;
    var weightBackground = 0;
    var maxVariance = 0.0;
    var threshold = 120;

    for (var i = 0; i < 256; i++) {
      weightBackground += histogram[i];
      if (weightBackground == 0) {
        continue;
      }

      final weightForeground = total - weightBackground;
      if (weightForeground == 0) {
        break;
      }

      sumBackground += i * histogram[i];
      final meanBackground = sumBackground / weightBackground;
      final meanForeground = (sum - sumBackground) / weightForeground;

      final varianceBetween =
          weightBackground *
          weightForeground *
          pow(meanBackground - meanForeground, 2);

      if (varianceBetween > maxVariance) {
        maxVariance = varianceBetween.toDouble();
        threshold = i;
      }
    }

    return threshold.clamp(65, 175).toDouble();
  }

  /// Dewarp + integral-image OMR scoring.
  ///
  /// 1. Perspective-correct the answer grid into a flat rectangular image
  ///    using bilinear interpolation from the 4 marker-derived corners.
  /// 2. Binarize with Otsu threshold computed on the dewarped image.
  /// 3. Build integral image of dark pixels.
  /// 4. Score each cell = dark_pixels / total_pixels in O(1) per cell.
  ///
  /// This uses EVERY pixel in each cell (not just sparse samples),
  /// giving maximum signal and near-perfect accuracy.
  List<List<double>> _computeAllCellScores({
    required _GrayImage gray,
    required _GridFrame grid,
    required double inset,
    int cellRes = 20,
  }) {
    // Step 1: Dewarp the grid area into a normalized rectangular image.
    final outW = _gridCols * cellRes;
    final outH = _gridRows * cellRes;

    final pixels = List<double>.filled(outW * outH, 255.0);
    for (var y = 0; y < outH; y++) {
      final v = (y + 0.5) / outH;
      for (var x = 0; x < outW; x++) {
        final u = (x + 0.5) / outW;
        final src = _mapFromGrid(u, v, grid);
        pixels[y * outW + x] = _bilinearAt(gray, src.dx, src.dy);
      }
    }
    final dewarped = _GrayImage(outW, outH, pixels);

    // Step 2: Adaptive local threshold (Bradley) on the dewarped answer area.
    // Each pixel is compared to its neighbourhood mean, making binarization
    // robust to uneven lighting across the 20×5 grid.
    final integral = _buildAdaptiveDarkIntegral(dewarped);

    // Step 4: Score each of the 20×5 cells.
    final insetPx = max(1, (cellRes * inset.clamp(0.10, 0.40)).round());
    final scores = List.generate(
      _gridCols,
      (_) => List<double>.filled(_gridRows, 0.0),
    );

    for (var q = 0; q < _gridCols; q++) {
      for (var o = 0; o < _gridRows; o++) {
        final x1 = q * cellRes + insetPx;
        final y1 = o * cellRes + insetPx;
        final x2 = (q + 1) * cellRes - insetPx;
        final y2 = (o + 1) * cellRes - insetPx;

        if (x2 <= x1 || y2 <= y1) continue;

        final darkCount = _integralRectSum(integral, outW, x1, y1, x2, y2);
        final totalPixels = (x2 - x1) * (y2 - y1);

        scores[q][o] = darkCount / totalPixels;
      }
    }

    return scores;
  }

  /// Answer picking with relative normalisation per question.
  ///
  /// Subtracting the per-question median removes any uniform darkness offset
  /// caused by paper colour or global lighting, so only the cell that is
  /// *relatively* darker than its siblings is detected as marked.
  /// An absolute floor (½ × minInkScore) still guards against all-dark rows.
  AnswerOption? _pickMarkedOption(
    List<double> scores,
    OMRScannerCalibration calibration,
  ) {
    // Median of the 5 options for this question (index 2 after sort).
    final sorted = [...scores]..sort();
    final median = sorted[2];

    // Relative scores: how much darker each option is vs. the median.
    final relative =
        scores.map((s) => (s - median).clamp(-1.0, 1.0)).toList();

    final indexed = relative.asMap().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final best = indexed[0];
    final secondBest = indexed[1];

    // Relative floor: best must stand out from the median.
    // Uses half of minInkScore because relative scores are smaller in magnitude.
    if (best.value < calibration.minInkScore * 0.5) return null;

    // Clear separation from runner-up (same gap metric, same calibration knob).
    if (best.value - secondBest.value < calibration.minGap) return null;

    return AnswerOption.values[best.key];
  }

  Offset _mapFromGrid(double u, double v, _GridFrame grid) {
    final top = Offset.lerp(grid.topLeft, grid.topRight, u)!;
    final bottom = Offset.lerp(grid.bottomLeft, grid.bottomRight, u)!;
    return Offset.lerp(top, bottom, v)!;
  }

  /// Bilinear interpolation at sub-pixel coordinates.
  /// Produces smoother dewarped cells than nearest-neighbor rounding,
  /// especially when the sheet is captured at a slight angle.
  double _bilinearAt(_GrayImage gray, double px, double py) {
    final x0 = px.floor().clamp(0, gray.width - 1);
    final x1 = (x0 + 1).clamp(0, gray.width - 1);
    final y0 = py.floor().clamp(0, gray.height - 1);
    final y1 = (y0 + 1).clamp(0, gray.height - 1);
    final fx = px - px.floorToDouble();
    final fy = py - py.floorToDouble();
    final v0 = gray.at(x0, y0) * (1 - fx) + gray.at(x1, y0) * fx;
    final v1 = gray.at(x0, y1) * (1 - fx) + gray.at(x1, y1) * fx;
    return v0 * (1 - fy) + v1 * fy;
  }

  /// Adaptive local threshold via Bradley's method.
  ///
  /// Instead of a single global Otsu value, each pixel is compared to the
  /// mean luminance of its [windowFraction]-th neighbourhood.  A pixel is
  /// considered dark when it is at least [bias]*100 % darker than the local
  /// mean.  This makes binarization robust to uneven lighting (e.g. phone
  /// flash creating a bright centre, shadows in corners).
  ///
  /// The result has the same layout as [_buildDarkIntegral] and can be
  /// consumed directly by [_integralRectSum].
  List<int> _buildAdaptiveDarkIntegral(
    _GrayImage gray, {
    double bias = 0.15,
    int windowFraction = 8,
  }) {
    final w = gray.width;
    final h = gray.height;

    // --- Build luminance integral for O(1) local-mean queries ---
    final lumIntegral = List<double>.filled(w * h, 0);
    for (var y = 0; y < h; y++) {
      var row = 0.0;
      for (var x = 0; x < w; x++) {
        row += gray.at(x, y);
        lumIntegral[y * w + x] =
            row + (y > 0 ? lumIntegral[(y - 1) * w + x] : 0);
      }
    }

    double lumRect(int x1, int y1, int x2, int y2) {
      if (x2 <= x1 || y2 <= y1) return 0;
      final ix2 = x2 - 1;
      final iy2 = y2 - 1;
      final a = lumIntegral[iy2 * w + ix2];
      final b = y1 > 0 ? lumIntegral[(y1 - 1) * w + ix2] : 0.0;
      final c = x1 > 0 ? lumIntegral[iy2 * w + (x1 - 1)] : 0.0;
      final d =
          (x1 > 0 && y1 > 0) ? lumIntegral[(y1 - 1) * w + (x1 - 1)] : 0.0;
      return a - b - c + d;
    }

    // Neighbourhood half-size: covers ~2.5 cells for typical dewarped images
    final half = max(2, w ~/ windowFraction);

    // --- Build dark-pixel integral using per-pixel adaptive threshold ---
    final integral = List<int>.filled(w * h, 0);
    for (var y = 0; y < h; y++) {
      var rowSum = 0;
      for (var x = 0; x < w; x++) {
        final x1 = max(0, x - half);
        final y1 = max(0, y - half);
        final x2 = min(w, x + half + 1);
        final y2 = min(h, y + half + 1);
        final area = (x2 - x1) * (y2 - y1);
        final localMean = lumRect(x1, y1, x2, y2) / area;
        // Pixel is dark when it is [bias]*100% below local mean
        rowSum += gray.at(x, y) < localMean * (1.0 - bias) ? 1 : 0;
        integral[y * w + x] =
            rowSum + (y > 0 ? integral[(y - 1) * w + x] : 0);
      }
    }
    return integral;
  }
}

class _GrayImage {
  _GrayImage(this.width, this.height, this._pixels);

  factory _GrayImage.fromImage(img.Image source) {
    final pixels = List<double>.filled(source.width * source.height, 0);
    var index = 0;

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final pixel = source.getPixel(x, y);
        pixels[index] = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        index++;
      }
    }

    return _GrayImage(source.width, source.height, pixels);
  }

  factory _GrayImage.fromLumaPlane({
    required int width,
    required int height,
    required int bytesPerRow,
    required Uint8List luminanceBytes,
  }) {
    final pixels = List<double>.filled(width * height, 0);
    var index = 0;

    for (var y = 0; y < height; y++) {
      final rowOffset = y * bytesPerRow;
      for (var x = 0; x < width; x++) {
        pixels[index] = luminanceBytes[rowOffset + x].toDouble();
        index++;
      }
    }

    return _GrayImage(width, height, pixels);
  }

  final int width;
  final int height;
  final List<double> _pixels;

  _GrayImage rotate90Clockwise() {
    final rotated = List<double>.filled(width * height, 0);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final newX = height - 1 - y;
        final newY = x;
        rotated[newY * height + newX] = at(x, y);
      }
    }

    return _GrayImage(height, width, rotated);
  }

  _GrayImage crop({
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    final pixels = List<double>.filled(width * height, 0);
    var index = 0;

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        pixels[index] = at(x + col, y + row);
        index++;
      }
    }

    return _GrayImage(width, height, pixels);
  }

  double at(int x, int y) {
    final safeX = x.clamp(0, width - 1);
    final safeY = y.clamp(0, height - 1);
    return _pixels[safeY * width + safeX];
  }
}

class _BlockCandidate {
  const _BlockCandidate({
    required this.x,
    required this.y,
    required this.size,
    required this.density,
  });

  final int x;
  final int y;
  final int size;
  final double density;
}

class _MarkerBox {
  const _MarkerBox({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    this.area,
  });

  final int left;
  final int right;
  final int top;
  final int bottom;
  final int? area;

  int get width => right - left + 1;
  int get height => bottom - top + 1;
  int get pixelCount => area ?? width * height;

  Offset get center => Offset((left + right) / 2, (top + bottom) / 2);
}

class _CornerMarkers {
  const _CornerMarkers({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.contentBounds,
  });

  final _MarkerBox topLeft;
  final _MarkerBox topRight;
  final _MarkerBox bottomLeft;
  final _MarkerBox bottomRight;
  final _ContentBounds contentBounds;
}

class _GridFrame {
  const _GridFrame({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  final Offset topLeft;
  final Offset topRight;
  final Offset bottomLeft;
  final Offset bottomRight;
}

class _ContentBounds {
  const _ContentBounds({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  final int left;
  final int right;
  final int top;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;
}

class _GuideCrop {
  const _GuideCrop({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final int x;
  final int y;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;
}
