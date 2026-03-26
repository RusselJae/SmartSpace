/// FAQ entry for support chat.
class Faq {
  final String id;
  final String question;
  final String answer;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Faq({
    required this.id,
    required this.question,
    required this.answer,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Faq.fromJson(Map<String, dynamic> json) {
    return Faq(
      id: json['id'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, String> toSupportChatMap() => {'q': question, 'a': answer};
}
