import '../entities/omr_scan_result.dart';

abstract class SheetReaderRepository {
  Future<OmrScanResult> scanSheet(String imagePath, {bool debug = false});
}
