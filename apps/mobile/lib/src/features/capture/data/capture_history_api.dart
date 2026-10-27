import '../../shared/mindos_api.dart';

/// A capture as the SERVER knows it (`GET /v1/captures`). Lets any device show
/// the user's full history, not only what its local outbox holds.
class ServerCapture {
  const ServerCapture({
    required this.id,
    required this.status,
    required this.createdAt,
    this.content,
    this.modality = 'text',
  });

  final String id;
  final String status;
  final DateTime createdAt;
  final String? content;
  final String modality;

  bool get isVoice => modality == 'voice';
  bool get isPending => status == 'raw' || status == 'processing';

  factory ServerCapture.fromJson(Map<String, dynamic> json) => ServerCapture(
        id: json['capture_id'] as String,
        status: (json['status'] as String?) ?? 'raw',
        createdAt: DateTime.parse(json['created_at'] as String),
        content: json['content'] as String?,
        modality: (json['modality'] as String?) ?? 'text',
      );
}

/// Read client for the user's capture history.
class CaptureHistoryApi {
  CaptureHistoryApi(this._api);
  final MindosApi _api;

  Future<List<ServerCapture>> recent({int limit = 20}) async {
    final json = await _api.get('/captures', query: {'limit': '$limit'})
        as Map<String, dynamic>;
    return (json['data'] as List<dynamic>? ?? [])
        .map((e) => ServerCapture.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
