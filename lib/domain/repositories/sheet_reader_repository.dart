import '../entities/answer_sheet.dart';

abstract class SheetReaderRepository {
  Future<AnswerSheet> readSheet(String imagePath);
}
