import '../../domain/entities/omr_scan_result.dart';
import '../../domain/repositories/sheet_reader_repository.dart';
import '../services/omr_native_channel.dart';

/// Reads an OMR answer sheet using the native Kotlin/OpenCV scanner.
class SheetReaderRepositoryImpl implements SheetReaderRepository {
  @override
  Future<OmrScanResult> scanSheet(String imagePath, {bool debug = false}) =>
      OmrNativeChannel.scanFull(imagePath, debug: debug);
}
