// Client-side models for "Ask mindOS" (mirrors POST /v1/query).

/// A capture the answer was grounded on (shown as a citation).
class AnswerSource {
  const AnswerSource({required this.captureId, required this.snippet});

  final String captureId;
  final String snippet;

  factory AnswerSource.fromJson(Map<String, dynamic> json) => AnswerSource(
        captureId: json['capture_id'] as String,
        snippet: (json['snippet'] as String?) ?? '',
      );
}

/// The assistant's grounded answer plus the notes it cited.
class QueryAnswer {
  const QueryAnswer({required this.answer, required this.sources});

  final String answer;
  final List<AnswerSource> sources;

  factory QueryAnswer.fromJson(Map<String, dynamic> json) => QueryAnswer(
        answer: (json['answer'] as String?)?.trim() ?? '',
        sources: (json['sources'] as List<dynamic>? ?? [])
            .map((e) => AnswerSource.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
