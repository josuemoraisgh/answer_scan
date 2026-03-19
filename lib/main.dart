import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/repositories/sheet_reader_repository_impl.dart';
import 'data/services/calibration_profile_store.dart';
import 'data/services/moodle_service.dart';
import 'data/services/moodle_session_store.dart';
import 'data/services/omr_sheet_scanner.dart';
import 'domain/usecases/grade_exam_usecase.dart';
import 'presentation/controllers/correction_controller.dart';
import 'presentation/controllers/moodle_controller.dart';
import 'presentation/pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final cameras = await availableCameras();
  final backCamera = cameras.where((camera) {
    return camera.lensDirection == CameraLensDirection.back;
  }).firstOrNull;

  final calibrationStore = CalibrationProfileStore();
  final calibration = await calibrationStore.load();
  final scanner = OMRSheetScanner(defaultCalibration: calibration);
  final repository = SheetReaderRepositoryImpl(scanner);
  final useCase = GradeExamUseCase();
  final controller = CorrectionController(
    repository: repository,
    gradeExamUseCase: useCase,
  );

  final moodleController = MoodleController(
    service: MoodleService(),
    store: MoodleSessionStore(),
  );
  await moodleController.loadSavedSession();

  runApp(
    CorretorProvaApp(
      controller: controller,
      moodleController: moodleController,
      camera: backCamera,
      scanner: scanner,
      calibrationStore: calibrationStore,
    ),
  );
}

class CorretorProvaApp extends StatelessWidget {
  const CorretorProvaApp({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Corretor de Provas',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: HomePage(
        controller: controller,
        moodleController: moodleController,
        camera: camera,
        scanner: scanner,
        calibrationStore: calibrationStore,
      ),
    );
  }
}
