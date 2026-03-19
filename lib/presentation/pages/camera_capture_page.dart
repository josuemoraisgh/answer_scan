import 'dart:collection';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/omr_capture_guide.dart';
import '../../data/services/omr_sheet_scanner.dart';

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({
    super.key,
    required this.camera,
    required this.title,
    this.scanner,
  });

  final CameraDescription camera;
  final String title;
  final OMRSheetScanner? scanner;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  static const _voteWindowSize = 5;
  static const _minVotesPerAnswer = 3;

  late final CameraController _cameraController;
  late final Future<void> _initializeFuture;

  bool _takingPhoto = false;
  bool _isProcessingLiveFrame = false;
  int _frameCounter = 0;
  OMRLiveGuideDebug? _liveGuide;
  bool _isLandscape = false;
  final Queue<Map<int, OMRLiveAnswerCell>> _liveAnswerHistory =
      Queue<Map<int, OMRLiveAnswerCell>>();

  @override
  void initState() {
    super.initState();
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _initializeFuture = _cameraController.initialize();
    _initializeFuture.then((_) => _startLiveDetection());
  }

  @override
  void dispose() {
    if (_cameraController.value.isStreamingImages) {
      _cameraController.stopImageStream();
    }
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _startLiveDetection() async {
    if (widget.scanner == null || !_cameraController.value.isInitialized) {
      return;
    }

    await _cameraController.startImageStream((image) async {
      if (_takingPhoto || _isProcessingLiveFrame) {
        return;
      }

      _frameCounter++;
      if (_frameCounter % 8 != 0) {
        return;
      }

      _isProcessingLiveFrame = true;

      try {
        final plane = image.planes.first;
        final rawGuide = widget.scanner!.detectLiveGuide(
          luminanceBytes: plane.bytes,
          width: image.width,
          height: image.height,
          bytesPerRow: plane.bytesPerRow,
          isLandscape: _isLandscape,
        );
        final liveGuide = _stabilizeWithFrameVoting(rawGuide);

        if (mounted) {
          setState(() {
            _liveGuide = liveGuide;
          });
        }
      } catch (_) {
        _liveAnswerHistory.clear();
        if (mounted) {
          setState(() {
            _liveGuide = null;
          });
        }
      } finally {
        _isProcessingLiveFrame = false;
      }
    });
  }

  OMRLiveGuideDebug _stabilizeWithFrameVoting(OMRLiveGuideDebug current) {
    final currentByQuestion = <int, OMRLiveAnswerCell>{
      for (final answer in current.detectedAnswers)
        answer.questionIndex: answer,
    };

    _liveAnswerHistory.addLast(currentByQuestion);
    while (_liveAnswerHistory.length > _voteWindowSize) {
      _liveAnswerHistory.removeFirst();
    }

    final votes = <int, Map<int, int>>{};
    final latestCellByChoice = <String, OMRLiveAnswerCell>{};

    for (final frame in _liveAnswerHistory) {
      frame.forEach((question, cell) {
        final byOption = votes.putIfAbsent(question, () => <int, int>{});
        byOption[cell.optionIndex] = (byOption[cell.optionIndex] ?? 0) + 1;
        latestCellByChoice['$question:${cell.optionIndex}'] = cell;
      });
    }

    final stabilized = <OMRLiveAnswerCell>[];

    for (final entry in votes.entries) {
      final q = entry.key;
      final byOption = entry.value;
      if (byOption.isEmpty) {
        continue;
      }

      var bestOption = -1;
      var bestVotes = 0;
      var secondVotes = 0;

      byOption.forEach((option, count) {
        if (count > bestVotes) {
          secondVotes = bestVotes;
          bestVotes = count;
          bestOption = option;
        } else if (count > secondVotes) {
          secondVotes = count;
        }
      });

      final hasMajority = bestVotes >= _minVotesPerAnswer;
      final hasSeparation = bestVotes > secondVotes;
      if (!hasMajority || !hasSeparation || bestOption < 0) {
        continue;
      }

      final currentCell = currentByQuestion[q];
      if (currentCell != null && currentCell.optionIndex == bestOption) {
        stabilized.add(currentCell);
        continue;
      }

      final fallback = latestCellByChoice['$q:$bestOption'];
      if (fallback != null) {
        stabilized.add(fallback);
      }
    }

    stabilized.sort((a, b) => a.questionIndex.compareTo(b.questionIndex));

    return OMRLiveGuideDebug(
      contentRect: current.contentRect,
      topLeftMarker: current.topLeftMarker,
      topRightMarker: current.topRightMarker,
      bottomLeftMarker: current.bottomLeftMarker,
      bottomRightMarker: current.bottomRightMarker,
      detectedAnswers: stabilized,
    );
  }

  Future<void> _capture() async {
    if (_takingPhoto) {
      return;
    }

    setState(() {
      _takingPhoto = true;
    });

    try {
      await _initializeFuture;
      if (_cameraController.value.isStreamingImages) {
        await _cameraController.stopImageStream();
      }
      final file = await _cameraController.takePicture();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(file.path);
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao tirar foto. Tente novamente.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _takingPhoto = false;
        });
      }
    }
  }

  Widget _buildFullBleedPreview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sensorAR = _cameraController.value.aspectRatio;
        final isPortraitLayout = constraints.maxHeight > constraints.maxWidth;
        // CameraPreview rotates automatically; effective AR flips in portrait
        final displayAR = isPortraitLayout ? (1 / sensorAR) : sensorAR;
        final parentAR = constraints.maxWidth / constraints.maxHeight;

        // Cover-fit: scale camera to fully fill available area, clip overflow
        double w, h;
        if (parentAR > displayAR) {
          w = constraints.maxWidth;
          h = constraints.maxWidth / displayAR;
        } else {
          h = constraints.maxHeight;
          w = constraints.maxHeight * displayAR;
        }

        return OverflowBox(
          alignment: Alignment.center,
          maxWidth: w,
          maxHeight: h,
          child: CameraPreview(_cameraController),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    _isLandscape = isLandscape;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<void>(
        future: _initializeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final cameraWithOverlay = ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildFullBleedPreview(),
                _GuideOverlay(liveGuide: _liveGuide),
              ],
            ),
          );

          final captureBtn = FloatingActionButton.large(
            onPressed: _takingPhoto ? null : _capture,
            child: _takingPhoto
                ? const CircularProgressIndicator()
                : const Icon(Icons.camera_alt),
          );

          if (isLandscape) {
            return Row(
              children: [
                Expanded(child: cameraWithOverlay),
                SafeArea(
                  left: false,
                  child: Container(
                    color: Colors.black,
                    width: 96,
                    child: Center(child: captureBtn),
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              Expanded(child: cameraWithOverlay),
              SafeArea(
                top: false,
                child: Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: captureBtn),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GuideOverlay extends StatelessWidget {
  const _GuideOverlay({this.liveGuide});

  final OMRLiveGuideDebug? liveGuide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Guide rect is always landscape-shaped (sheet is wider than tall)
        double guideWidth = constraints.maxWidth * OMRCaptureGuide.widthFactor;
        double guideHeight = guideWidth * OMRCaptureGuide.heightFromWidthFactor;

        // If height exceeds available space, scale down proportionally
        final maxHeight = constraints.maxHeight * 0.85;
        if (guideHeight > maxHeight) {
          guideHeight = maxHeight;
          guideWidth = guideHeight / OMRCaptureGuide.heightFromWidthFactor;
        }

        return Center(
          child: SizedBox(
            width: guideWidth,
            height: guideHeight,
            child: CustomPaint(
              painter: _LiveGuidePainter(liveGuide: liveGuide),
            ),
          ),
        );
      },
    );
  }
}

class _LiveGuidePainter extends CustomPainter {
  const _LiveGuidePainter({required this.liveGuide});

  final OMRLiveGuideDebug? liveGuide;

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = liveGuide == null ? Colors.white : Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawRect(Offset.zero & size, borderPaint);

    final guide = liveGuide;
    if (guide == null) {
      return;
    }

    final contentPaint = Paint()
      ..color = Colors.lightBlueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(_mapRect(guide.contentRect, size), contentPaint);

    final markerPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final pointPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;

    for (final marker in [
      guide.topLeftMarker,
      guide.topRightMarker,
      guide.bottomLeftMarker,
      guide.bottomRightMarker,
    ]) {
      final rect = _mapRect(marker, size);
      canvas.drawRect(rect, markerPaint);
      canvas.drawCircle(rect.center, 5, pointPaint);
    }

    // Draw green filled rectangles at detected answer positions
    if (guide.detectedAnswers.isNotEmpty) {
      final answerFillPaint = Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      final answerStrokePaint = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      for (final answer in guide.detectedAnswers) {
        final rect = _mapRect(answer.rect, size);
        canvas.drawRect(rect, answerFillPaint);
        canvas.drawRect(rect, answerStrokePaint);
      }
    }
  }

  Rect _mapRect(OMRDebugRect rect, Size size) {
    return Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );
  }

  @override
  bool shouldRepaint(covariant _LiveGuidePainter oldDelegate) {
    return oldDelegate.liveGuide != liveGuide;
  }
}
