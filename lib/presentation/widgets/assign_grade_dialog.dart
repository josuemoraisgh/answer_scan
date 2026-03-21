import 'package:flutter/material.dart';

import '../../data/models/moodle_models.dart';
import '../../domain/usecases/grade_exam_usecase.dart';
import '../controllers/moodle_controller.dart';

class AssignGradeDialog extends StatefulWidget {
  const AssignGradeDialog({
    super.key,
    required this.moodleController,
    required this.result,
  });

  final MoodleController moodleController;
  final GradeResult result;

  @override
  State<AssignGradeDialog> createState() => _AssignGradeDialogState();
}

class _AssignGradeDialogState extends State<AssignGradeDialog> {
  MoodleStudent? _selected;
  final _searchCtrl = TextEditingController();
  List<MoodleStudent> _filtered = [];

  MoodleController get ctrl => widget.moodleController;

  @override
  void initState() {
    super.initState();
    _filtered = ctrl.students;
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = ctrl.students
          .where(
            (s) =>
                s.fullname.toLowerCase().contains(q) ||
                s.email.toLowerCase().contains(q),
          )
          .toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = ctrl.selectedGradeItem!;
    final grade =
        (widget.result.correctAnswers / widget.result.totalQuestions) *
        item.gradeMax;

    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) => AlertDialog(
        title: const Text('Enviar nota ao Moodle'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Grade summary card ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  children: [
                    Text(
                      '${widget.result.correctAnswers} / '
                      '${widget.result.totalQuestions} corretas',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Nota: ${grade.toStringAsFixed(1)} '
                      '/ ${item.gradeMax.toStringAsFixed(0)}',
                      style: TextStyle(color: Colors.green.shade800),
                    ),
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Student search ──────────────────────────────────────────
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Buscar aluno',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 8),

              // ── Student list ────────────────────────────────────────────
              SizedBox(
                height: 220,
                child: ctrl.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ctrl.students.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Nenhum aluno carregado.'),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: ctrl.reloadStudents,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Carregar alunos'),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final s = _filtered[i];
                          final isSelected = _selected == s;
                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: Colors.teal.shade50,
                            leading: Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: isSelected ? Colors.teal : Colors.grey,
                            ),
                            title: Text(
                              s.fullname,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              s.email,
                              style: const TextStyle(fontSize: 12),
                            ),
                            dense: true,
                            onTap: () => setState(() => _selected = s),
                          );
                        },
                      ),
              ),

              // ── Feedback message ────────────────────────────────────────
              if (ctrl.lastSubmitMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  ctrl.lastSubmitMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: ctrl.lastSubmitMessage!.startsWith('Nota enviada')
                        ? Colors.green.shade700
                        : Colors.red,
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Actions ─────────────────────────────────────────────────────
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
          FilledButton.icon(
            onPressed: (_selected == null || ctrl.isSubmitting)
                ? null
                : _submit,
            icon: ctrl.isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send),
            label: const Text('Enviar nota'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final ok = await ctrl.submitGrade(
      studentId: _selected!.id,
      correctAnswers: widget.result.correctAnswers,
      totalQuestions: widget.result.totalQuestions,
    );
    if (ok && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nota enviada com sucesso!')),
      );
    }
  }
}
