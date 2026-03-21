import '../../domain/entities/answer_sheet.dart';
import '../../domain/repositories/sheet_reader_repository.dart';
import '../services/omr_native_channel.dart';

/// Reads an OMR answer sheet using the native Kotlin/OpenCV scanner
/// via [OmrNativeChannel].
class SheetReaderRepositoryImpl implements SheetReaderRepository {
  @override
  Future<AnswerSheet> readSheet(String imagePath) =>
      OmrNativeChannel.scan(imagePath);
}
