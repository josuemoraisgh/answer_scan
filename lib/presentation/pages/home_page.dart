import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../data/services/calibration_profile_store.dart';
import '../../data/services/omr_sheet_scanner.dart';
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
    required this.scanner,
    required this.calibrationStore,
  });

  final CorrectionController controller;
  final MoodleController moodleController;
  final CameraDescription? camera;
  final OMRSheetScanner scanner;
  final CalibrationProfileStore calibrationStore;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> _captureAnswerKey() async {
    final path = await _openCamera('Capturar gabarito');
    if (path == null) return;
    await widget.controller.loadAnswerKey(path);
  }

  Future<void> _captureStudentSheet() async {
    final path = await _openCamera('Capturar respostas do aluno');
    if (path == null) return;
    await widget.controller.loadStudentSheet(path);
  }

  Future<String?> _openCamera(String title) async {
    final camera = widget.camera;
    if (camera == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma camera disponivel.')),
        );
      }
      return null;
    }
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CameraCapturePage(
          camera: camera,
          title: title,
          scanner: widget.scanner,
        ),
      ),
    );
  }

  void _openCalibration() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalibrationPage(
          camera: widget.camera,
          scanner: widget.scanner,
          calibrationStore: widget.calibrationStore,
        ),
      ),
    );
  }

  void _openMoodle() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MoodleConnectPage(controller: widget.moodleController),
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
      animation: Listenable.merge(
          [widget.controller, widget.moodleController]),
      builder: (context, _) {
        final result = widget.controller.result;
        final moodle = widget.moodleController;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Corretor de Provas OMR'),
            actions: [
              _MoodleStatusButton(
                controller: moodle,
                onTap: _openMoodle,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '1) Capture o gabarito\n2) Capture a folha do aluno\n3) Toque em Corrigir',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      widget.controller.isBusy ? null : _captureAnswerKey,
                  icon: const Icon(Icons.fact_check),
                  label: const Text('Ler gabarito'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: widget.controller.isBusy
                      ? null
                      : _captureStudentSheet,
                  icon: const Icon(Icons.assignment),
                  label: const Text('Ler folha do aluno'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: widget.controller.isBusy ||
                          !widget.controller.canGrade
                      ? null
                      : () {
                          widget.controller.grade();
                          final result = widget.controller.result;
                          if (result != null &&
                              widget.moodleController.isFullyConfigured) {
                            _openAssignGrade(result);
                          }
                        },
                  icon: const Icon(Icons.done_all),
                  label: const Text('Corrigir'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed:
                      widget.controller.isBusy ? null : _openCalibration,
                  icon: const Icon(Icons.tune),
                  label: const Text('Tela de calibracao'),
                ),
                if (widget.controller.isBusy) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (widget.controller.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    widget.controller.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 24),
                _SummaryCard(
                  title: 'Gabarito lido',
                  content: widget.controller.answerKeySummary,
                ),
                const SizedBox(height: 12),
                _SummaryCard(
                  title: 'Folha do aluno lida',
                  content: widget.controller.studentSummary,
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

// ──────────────────────────────────────────────────────────────────────────────
// AppBar Moodle status button
// ──────────────────────────────────────────────────────────────────────────────

class _MoodleStatusButton extends StatelessWidget {
  const _MoodleStatusButton({
    required this.controller,
    required this.onTap,
  });

  final MoodleController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final connected = controller.isFullyConfigured;
    return IconButton(
      onPressed: onTap,
      tooltip: connected ? 'Moodle conectado' : 'Conectar ao Moodle',
      icon: Icon(
        Icons.school,
        color: connected ? Colors.greenAccent : null,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Existing cards (unchanged)
// ──────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(content),
          ],
        ),
      ),
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
