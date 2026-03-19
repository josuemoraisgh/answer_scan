import 'package:flutter_test/flutter_test.dart';

import 'package:answer_scan/domain/entities/answer_sheet.dart';
import 'package:answer_scan/domain/repositories/sheet_reader_repository.dart';
import 'package:answer_scan/domain/usecases/grade_exam_usecase.dart';
import 'package:answer_scan/data/services/calibration_profile_store.dart';
import 'package:answer_scan/data/services/moodle_service.dart';
import 'package:answer_scan/data/services/moodle_session_store.dart';
import 'package:answer_scan/data/services/omr_sheet_scanner.dart';
import 'package:answer_scan/main.dart';
import 'package:answer_scan/presentation/controllers/correction_controller.dart';
import 'package:answer_scan/presentation/controllers/moodle_controller.dart';

void main() {
  testWidgets('exibe titulo principal', (WidgetTester tester) async {
    final controller = CorrectionController(
      repository: _FakeSheetReaderRepository(),
      gradeExamUseCase: GradeExamUseCase(),
    );
    final moodleController = MoodleController(
      service: MoodleService(),
      store: MoodleSessionStore(),
    );

    await tester.pumpWidget(
      CorretorProvaApp(
        controller: controller,
        moodleController: moodleController,
        camera: null,
        scanner: OMRSheetScanner(),
        calibrationStore: CalibrationProfileStore(),
      ),
    );

    expect(find.text('Corretor de Provas OMR'), findsOneWidget);
  });
}

class _FakeSheetReaderRepository implements SheetReaderRepository {
  @override
  Future<AnswerSheet> readSheet(String imagePath) {
    throw UnimplementedError();
  }
}
