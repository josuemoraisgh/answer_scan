import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/sheet_scan_session.dart';
import '../../domain/usecases/grade_exam_usecase.dart';
import '../controllers/correction_controller.dart';
import '../controllers/moodle_controller.dart';
import '../widgets/assign_grade_dialog.dart';
import 'calibration_page.dart';
import 'camera_capture_page.dart';
import 'moodle_connect_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.moodleController,
    required this.camera,
  });

  final CorrectionController controller;
  final MoodleController moodleController;
  final CameraDescription? camera;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _debugMode = false;

  Future<void> _captureAnswerKey() => _captureSheet(_SheetTarget.answerKey);

  Future<void> _pickAnswerKey() => _pickSheet(_SheetTarget.answerKey);

  Future<void> _captureStudentSheet() => _captureSheet(_SheetTarget.student);

  Future<void> _pickStudentSheet() => _pickSheet(_SheetTarget.student);

  Future<void> _captureSheet(_SheetTarget target) async {
    final camera = widget.camera;
    if (camera == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma camera disponivel.')),
        );
      }
      return;
    }

    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            CameraCapturePage(camera: camera, title: target.cameraTitle),
      ),
    );

    if (path == null) {
      return;
    }

    await _scanImage(target, path);
  }

  Future<void> _pickSheet(_SheetTarget target) async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (file == null) {
      return;
    }

    await _scanImage(target, file.path);
  }

  Future<void> _scanImage(_SheetTarget target, String imagePath) async {
    if (target == _SheetTarget.answerKey) {
      await widget.controller.loadAnswerKey(imagePath, debug: _debugMode);
      return;
    }

    await widget.controller.loadStudentSheet(imagePath, debug: _debugMode);
  }

  void _openCalibration() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CalibrationPage(camera: widget.camera)),
    );
  }

  void _openMoodle() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MoodleConnectPage(controller: widget.moodleController),
      ),
    );
  }

  void _openAssignGrade(GradeResult result) {
    showDialog<void>(
      context: context,
      builder: (_) => AssignGradeDialog(
        moodleController: widget.moodleController,
        result: result,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.moodleController]),
      builder: (context, _) {
        final result = widget.controller.result;
        final moodle = widget.moodleController;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Corretor de Provas OMR'),
            actions: [
              _MoodleStatusButton(controller: moodle, onTap: _openMoodle),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WorkflowCard(
                  debugMode: _debugMode,
                  onDebugChanged: (value) {
                    setState(() {
                      _debugMode = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _ScanActionCard(
                  title: 'Gabarito',
                  subtitle: 'Leia a folha mestre usando camera ou galeria.',
                  onCamera: widget.controller.isBusy ? null : _captureAnswerKey,
                  onGallery: widget.controller.isBusy ? null : _pickAnswerKey,
                ),
                const SizedBox(height: 12),
                _ScanActionCard(
                  title: 'Folha do aluno',
                  subtitle: 'Use o mesmo template fixo com 20 questoes.',
                  onCamera: widget.controller.isBusy
                      ? null
                      : _captureStudentSheet,
                  onGallery: widget.controller.isBusy
                      ? null
                      : _pickStudentSheet,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      widget.controller.isBusy || !widget.controller.canGrade
                      ? null
                      : () {
                          widget.controller.grade();
                          final scanResult = widget.controller.result;
                          if (scanResult != null &&
                              widget.moodleController.isFullyConfigured) {
                            _openAssignGrade(scanResult);
                          }
                        },
                  icon: const Icon(Icons.done_all),
                  label: const Text('Corrigir'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: widget.controller.isBusy ? null : _openCalibration,
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('Diagnostico nativo'),
                ),
                if (widget.controller.isBusy) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (widget.controller.statusMessage != null) ...[
                  const SizedBox(height: 16),
                  _StatusBanner(
                    message: widget.controller.statusMessage!,
                    color: const Color(0xFF0D6E5B),
                  ),
                ],
                if (widget.controller.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  _StatusBanner(
                    message: widget.controller.errorMessage!,
                    color: Colors.red.shade700,
                  ),
                ],
                const SizedBox(height: 20),
                _ScanSummaryCard(
                  title: 'Gabarito lido',
                  session: widget.controller.answerKeyScan,
                ),
                const SizedBox(height: 12),
                _ScanSummaryCard(
                  title: 'Folha do aluno lida',
                  session: widget.controller.studentSheetScan,
                ),
                const SizedBox(height: 20),
                if (result != null) _ResultCard(result: result),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _SheetTarget {
  answerKey('Capturar gabarito'),
  student('Capturar respostas do aluno');

  const _SheetTarget(this.cameraTitle);

  final String cameraTitle;
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({required this.debugMode, required this.onDebugChanged});

  final bool debugMode;
  final ValueChanged<bool> onDebugChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fluxo offline',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              '1) Capture ou selecione a imagem.\n'
              '2) O Kotlin/OpenCV detecta os 4 marcadores.\n'
              '3) A folha e retificada por homografia.\n'
              '4) O grid fixo 20 x 5 e lido offline.',
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Salvar debug nativo'),
              subtitle: const Text(
                'Gera imagem com binarizacao, homografia e ROIs desenhadas.',
              ),
              value: debugMode,
              onChanged: onDebugChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanActionCard extends StatelessWidget {
  const _ScanActionCard({
    required this.title,
    required this.subtitle,
    required this.onCamera,
    required this.onGallery,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onCamera;
  final VoidCallback? onGallery;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCamera,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galeria'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanSummaryCard extends StatelessWidget {
  const _ScanSummaryCard({required this.title, required this.session});

  final String title;
  final SheetScanSession? session;

  @override
  Widget build(BuildContext context) {
    final debugPath = session?.result.debugImagePath;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (session == null)
              const Text('Nenhuma leitura.')
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    label: 'Status',
                    value: _statusLabel(session!.result.sheetStatus),
                  ),
                  _MetricChip(
                    label: 'Marcadores',
                    value: '${session!.result.markersDetected}/4',
                  ),
                  _MetricChip(
                    label: 'Perspectiva',
                    value: session!.result.perspectiveCorrected
                        ? 'corrigida'
                        : 'pendente',
                  ),
                  _MetricChip(
                    label: 'Confianca media',
                    value:
                        '${(session!.result.averageConfidence * 100).toStringAsFixed(0)}%',
                  ),
                  _MetricChip(
                    label: 'Revisao',
                    value: '${session!.result.unresolvedCount}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Arquivo: ${_basename(session!.imagePath)}'),
              const SizedBox(height: 8),
              SelectableText(session!.result.summary),
              if (session!.result.reviewQuestionNumbers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Revisar: ${session!.result.reviewQuestionNumbers.map((q) => 'Q$q').join(', ')}',
                ),
              ],
              if (debugPath != null && File(debugPath).existsSync()) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(debugPath), fit: BoxFit.cover),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _basename(String path) {
    final separator = Platform.pathSeparator;
    final parts = path.split(separator);
    return parts.isEmpty ? path : parts.last;
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'ok':
        return 'ok';
      case 'review_required':
        return 'revisar';
      case 'blurry':
        return 'borrada';
      case 'markers_not_found':
        return 'sem marcadores';
      case 'perspective_invalid':
        return 'perspectiva ruim';
      default:
        return status;
    }
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $value'));
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(message, style: TextStyle(color: color)),
    );
  }
}

class _MoodleStatusButton extends StatelessWidget {
  const _MoodleStatusButton({required this.controller, required this.onTap});

  final MoodleController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final connected = controller.isFullyConfigured;
    return IconButton(
      onPressed: onTap,
      tooltip: connected ? 'Moodle conectado' : 'Conectar ao Moodle',
      icon: Icon(Icons.school, color: connected ? Colors.greenAccent : null),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final GradeResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              'Resultado da Correcao',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '${result.correctAnswers} de ${result.totalQuestions} questoes corretas',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
