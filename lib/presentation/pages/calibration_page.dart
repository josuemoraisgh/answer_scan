import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../data/services/calibration_profile_store.dart';
import '../../data/services/omr_sheet_scanner.dart';
import '../../domain/entities/answer_option.dart';
import 'camera_capture_page.dart';

class CalibrationPage extends StatefulWidget {
  const CalibrationPage({
    super.key,
    required this.camera,
    required this.scanner,
    required this.calibrationStore,
  });

  final CameraDescription? camera;
  final OMRSheetScanner scanner;
  final CalibrationProfileStore calibrationStore;

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  late OMRScannerCalibration _calibration;
  OMRScanDebugResult? _debugResult;
  String? _imagePath;
  String? _error;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _calibration = widget.scanner.defaultCalibration;
  }

  Future<void> _captureAndAnalyze() async {
    final camera = widget.camera;
    if (camera == null) {
      setState(() {
        _error = 'Nenhuma camera disponivel para calibracao.';
      });
      return;
    }

    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CameraCapturePage(
          camera: camera,
          title: 'Capturar folha para calibracao',
          scanner: widget.scanner,
        ),
      ),
    );

    if (path == null) {
      return;
    }

    setState(() {
      _imagePath = path;
    });

    await _reanalyze();
  }

  Future<void> _reanalyze() async {
    final imagePath = _imagePath;
    if (imagePath == null) {
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      final result = await widget.scanner.scanWithDebug(
        imagePath,
        calibration: _calibration,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _debugResult = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'Falha na calibracao: $error';
        _debugResult = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _updateCalibration(OMRScannerCalibration next) async {
    setState(() {
      _calibration = next;
    });

    await _reanalyze();
  }

  Future<void> _saveCalibrationProfile() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      await widget.calibrationStore.save(_calibration);
      widget.scanner.setDefaultCalibration(_calibration);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil de calibracao salvo com sucesso.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'Falha ao salvar perfil: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _debugResult;

    return Scaffold(
      appBar: AppBar(title: const Text('Calibracao OMR')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _isBusy ? null : _captureAndAnalyze,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Capturar folha de calibracao'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isBusy || _imagePath == null ? null : _reanalyze,
              icon: const Icon(Icons.refresh),
              label: const Text('Reprocessar com parametros atuais'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isBusy ? null : _saveCalibrationProfile,
              icon: const Icon(Icons.save),
              label: const Text('Salvar perfil de calibracao'),
            ),
            const SizedBox(height: 16),
            if (_imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: result?.imageAspectRatio ?? 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(File(_imagePath!), fit: BoxFit.fill),
                      if (result != null)
                        CustomPaint(
                          painter: _CalibrationOverlayPainter(
                            geometry: result.geometry,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_isBusy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            Text(
              'Parametros de Calibracao',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _SliderSetting(
              label: 'Ajuste do threshold',
              valueLabel: _calibration.thresholdBias.toStringAsFixed(1),
              value: _calibration.thresholdBias,
              min: -35,
              max: 35,
              onChanged: (value) async {
                await _updateCalibration(
                  _calibration.copyWith(thresholdBias: value),
                );
              },
            ),
            _SliderSetting(
              label: 'Tinta minima para considerar marcada',
              valueLabel: _calibration.minInkScore.toStringAsFixed(3),
              value: _calibration.minInkScore,
              min: 0.03,
              max: 0.20,
              onChanged: (value) async {
                await _updateCalibration(
                  _calibration.copyWith(minInkScore: value),
                );
              },
            ),
            _SliderSetting(
              label: 'Diferenca minima entre 1a e 2a opcao',
              valueLabel: _calibration.minGap.toStringAsFixed(3),
              value: _calibration.minGap,
              min: 0.01,
              max: 0.10,
              onChanged: (value) async {
                await _updateCalibration(_calibration.copyWith(minGap: value));
              },
            ),
            _SliderSetting(
              label: 'Margem interna da celula',
              valueLabel: _calibration.cellInset.toStringAsFixed(2),
              value: _calibration.cellInset,
              min: 0.15,
              max: 0.42,
              onChanged: (value) async {
                await _updateCalibration(
                  _calibration.copyWith(cellInset: value),
                );
              },
            ),
            const SizedBox(height: 16),
            if (result != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Threshold final: ${result.threshold.toStringAsFixed(1)}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Questoes ambiguas: ${_ambiguousQuestions(result).length}',
                      ),
                      const SizedBox(height: 8),
                      Text('Resumo lido: ${_summary(result)}'),
                    ],
                  ),
                ),
              ),
              if (_ambiguousQuestions(result).isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Revisao rapida das ambiguas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ambiguousQuestions(result).map((question) {
                    return Chip(
                      backgroundColor: Colors.orange.shade100,
                      label: Text(
                        'Q${question.questionNumber}: gap ${question.scoreGap.toStringAsFixed(3)}',
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Diagnostico por questao',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...result.questions.map(_buildQuestionCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(OMRQuestionDebugResult question) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Q${question.questionNumber.toString().padLeft(2, '0')} -> ${question.marked?.label ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: List.generate(question.optionScores.length, (index) {
                final label = AnswerOption.values[index].label;
                final score = question.optionScores[index];
                return Chip(
                  label: Text('$label: ${score.toStringAsFixed(3)}'),
                  backgroundColor: question.marked?.index == index
                      ? Colors.teal.shade100
                      : null,
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  String _summary(OMRScanDebugResult result) {
    final buffer = StringBuffer();
    for (var i = 0; i < result.questions.length; i++) {
      final label = result.questions[i].marked?.label ?? '-';
      buffer.write('${i + 1}:$label');
      if (i < result.questions.length - 1) {
        buffer.write('  ');
      }
    }
    return buffer.toString();
  }

  List<OMRQuestionDebugResult> _ambiguousQuestions(OMRScanDebugResult result) {
    return result.questions.where((question) {
      return question.marked == null || question.scoreGap < 0.025;
    }).toList();
  }
}

class _CalibrationOverlayPainter extends CustomPainter {
  const _CalibrationOverlayPainter({required this.geometry});

  final OMRDebugGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final contentPaint = Paint()
      ..color = Colors.lightBlueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final gridPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final markerPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final pointPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    canvas.drawRect(_mapRect(geometry.guideRect, size), guidePaint);
    canvas.drawRect(_mapRect(geometry.contentRect, size), contentPaint);

    for (final marker in [
      geometry.topLeftMarker,
      geometry.topRightMarker,
      geometry.bottomLeftMarker,
      geometry.bottomRightMarker,
    ]) {
      canvas.drawRect(_mapRect(marker, size), markerPaint);
    }

    final gridPath = Path()
      ..moveTo(
        geometry.gridTopLeft.x * size.width,
        geometry.gridTopLeft.y * size.height,
      )
      ..lineTo(
        geometry.gridTopRight.x * size.width,
        geometry.gridTopRight.y * size.height,
      )
      ..lineTo(
        geometry.gridBottomRight.x * size.width,
        geometry.gridBottomRight.y * size.height,
      )
      ..lineTo(
        geometry.gridBottomLeft.x * size.width,
        geometry.gridBottomLeft.y * size.height,
      )
      ..close();
    canvas.drawPath(gridPath, gridPaint);

    for (final point in [
      geometry.gridTopLeft,
      geometry.gridTopRight,
      geometry.gridBottomLeft,
      geometry.gridBottomRight,
    ]) {
      canvas.drawCircle(
        Offset(point.x * size.width, point.y * size.height),
        math.max(4, size.shortestSide * 0.008),
        pointPaint,
      );
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
  bool shouldRepaint(covariant _CalibrationOverlayPainter oldDelegate) {
    return oldDelegate.geometry != geometry;
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $valueLabel'),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}
