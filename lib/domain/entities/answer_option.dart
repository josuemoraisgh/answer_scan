enum AnswerOption { a, b, c, d, e }

extension AnswerOptionLabel on AnswerOption {
  String get label {
    switch (this) {
      case AnswerOption.a:
        return 'A';
      case AnswerOption.b:
        return 'B';
      case AnswerOption.c:
        return 'C';
      case AnswerOption.d:
        return 'D';
      case AnswerOption.e:
        return 'E';
    }
  }
}
