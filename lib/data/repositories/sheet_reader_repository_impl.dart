import '../../domain/entities/answer_sheet.dart';
import '../../domain/repositories/sheet_reader_repository.dart';
import '../services/omr_sheet_scanner.dart';

class SheetReaderRepositoryImpl implements SheetReaderRepository {
  SheetReaderRepositoryImpl(this._scanner);

  final OMRSheetScanner _scanner;

  @override
  Future<AnswerSheet> readSheet(String imagePath) {
    return _scanner.scan(imagePath);
  }
}
