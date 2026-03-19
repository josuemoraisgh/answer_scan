import 'package:flutter/foundation.dart';

import '../../domain/entities/answer_option.dart';
import '../../domain/entities/answer_sheet.dart';
import '../../domain/repositories/sheet_reader_repository.dart';
import '../../domain/usecases/grade_exam_usecase.dart';

class CorrectionController extends ChangeNotifier {
  CorrectionController({
    required SheetReaderRepository repository,
    required GradeExamUseCase gradeExamUseCase,
  }) : _repository = repository,
       _gradeExamUseCase = gradeExamUseCase;

  final SheetReaderRepository _repository;
  final GradeExamUseCase _gradeExamUseCase;

  AnswerSheet? _answerKey;
  AnswerSheet? _studentSheet;
  GradeResult? _result;
  String? _errorMessage;
  bool _isBusy = false;

  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  GradeResult? get result => _result;

  bool get canGrade => _answerKey != null && _studentSheet != null;

  String get answerKeySummary => _sheetSummary(_answerKey);
  String get studentSummary => _sheetSummary(_studentSheet);

  Future<void> loadAnswerKey(String imagePath) async {
    await _loadSheet(
      imagePath: imagePath,
      onSuccess: (sheet) {
        _answerKey = sheet;
        _result = null;
      },
    );
  }

  Future<void> loadStudentSheet(String imagePath) async {
    await _loadSheet(
      imagePath: imagePath,
      onSuccess: (sheet) {
        _studentSheet = sheet;
        _result = null;
      },
    );
  }

  void grade() {
    _errorMessage = null;

    if (!canGrade) {
      _errorMessage = 'Leia o gabarito e a folha do aluno antes de corrigir.';
      notifyListeners();
      return;
    }

    _result = _gradeExamUseCase.execute(
      answerKey: _answerKey!,
      studentSheet: _studentSheet!,
    );

    notifyListeners();
  }

  Future<void> _loadSheet({
    required String imagePath,
    required void Function(AnswerSheet sheet) onSuccess,
  }) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final sheet = await _repository.readSheet(imagePath);
      onSuccess(sheet);
    } catch (error) {
      _errorMessage = 'Falha na leitura: $error';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  String _sheetSummary(AnswerSheet? sheet) {
    if (sheet == null) {
      return 'Nenhuma leitura.';
    }

    final text = StringBuffer();
    for (var i = 0; i < sheet.answers.length; i++) {
      final answer = sheet.answers[i];
      final label = answer == null ? '-' : answer.label;
      text.write('${i + 1}:$label');
      if (i < sheet.answers.length - 1) {
        text.write('  ');
      }
    }

    return text.toString();
  }
}
