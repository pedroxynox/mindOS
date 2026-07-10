// Client-side models for the AI-derived knowledge graph
// (mirrors the API's `/v1/graph/*` responses).

/// A derived node: a person, task, project, event, topic, note or decision the
/// understanding pipeline extracted from the user's captures.
class GraphNode {
  const GraphNode({
    required this.id,
    required this.type,
    required this.title,
    this.confidence,
    this.occurredAt,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String? title;
  final double? confidence;
  final DateTime? occurredAt;
  final DateTime createdAt;

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      occurredAt: json['occurred_at'] != null
          ? DateTime.tryParse(json['occurred_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// A semantic relationship between two derived nodes.
class GraphEdge {
  const GraphEdge({
    required this.source,
    required this.target,
    required this.type,
    this.confidence,
  });

  final String source;
  final String target;
  final String type;
  final double? confidence;

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      source: json['source'] as String,
      target: json['target'] as String,
      type: json['type'] as String,
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }
}

/// Per-type counts of derived nodes, for the home overview.
class GraphSummary {
  const GraphSummary({required this.counts, required this.total});

  final Map<String, int> counts;
  final int total;

  factory GraphSummary.fromJson(Map<String, dynamic> json) {
    final raw = (json['counts'] as Map<String, dynamic>? ?? {});
    return GraphSummary(
      counts: raw.map((k, v) => MapEntry(k, (v as num).toInt())),
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A page of derived nodes of one type.
class GraphNodePage {
  const GraphNodePage({required this.data, this.nextCursor});

  final List<GraphNode> data;
  final String? nextCursor;
}

/// What the brain extracted from one capture: its pipeline [status], the derived
/// [nodes] and the semantic [edges] connecting them.
class CaptureEntities {
  const CaptureEntities({
    required this.captureId,
    required this.status,
    required this.nodes,
    required this.edges,
  });

  final String captureId;
  final String status;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  /// True while the pipeline is still working (raw / processing).
  bool get isPending => status == 'raw' || status == 'processing';
  bool get isFailed => status == 'failed';

  factory CaptureEntities.fromJson(Map<String, dynamic> json) {
    return CaptureEntities(
      captureId: json['capture_id'] as String,
      status: json['status'] as String,
      nodes: (json['nodes'] as List<dynamic>? ?? [])
          .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List<dynamic>? ?? [])
          .map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
