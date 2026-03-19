import 'answer_option.dart';

class AnswerSheet {
  AnswerSheet(List<AnswerOption?> answers)
    : _answers = List<AnswerOption?>.unmodifiable(answers) {
    if (_answers.length != totalQuestions) {
      throw ArgumentError(
        'A folha precisa ter exatamente $totalQuestions respostas.',
      );
    }
  }

  static const int totalQuestions = 20;

  final List<AnswerOption?> _answers;

  List<AnswerOption?> get answers => _answers;
}
