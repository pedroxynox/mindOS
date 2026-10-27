// Client-side models for the AI-derived knowledge graph
// (mirrors the API's `/v1/graph/*` responses).

/// A derived node: a person, task, project, event, topic, note or decision the
/// understanding pipeline extracted from the user's captures.
///
/// In lists, people/projects/events/topics/decisions come grouped by name
/// across captures: [mentions] says how many times the user mentioned it.
class GraphNode {
  const GraphNode({
    required this.id,
    required this.type,
    required this.title,
    this.confidence,
    this.occurredAt,
    required this.createdAt,
    this.mentions = 1,
  });

  final String id;
  final String type;
  final String? title;
  final double? confidence;
  final DateTime? occurredAt;
  final DateTime createdAt;
  final int mentions;

  /// Title for display, never empty.
  String get label =>
      (title ?? '').trim().isEmpty ? '(sin título)' : title!.trim();

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
      mentions: (json['mentions'] as num?)?.toInt() ?? 1,
    );
  }
}

/// A semantic relationship between two derived nodes.
class GraphEdge {
  const GraphEdge({
    this.id,
    required this.source,
    required this.target,
    required this.type,
    this.confidence,
    this.userConfirmed = false,
  });

  /// Null only for responses from an API older than the corrections release.
  final String? id;
  final String source;
  final String target;
  final String type;
  final double? confidence;
  final bool userConfirmed;

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      id: json['id'] as String?,
      source: json['source'] as String,
      target: json['target'] as String,
      type: json['type'] as String,
      confidence: (json['confidence'] as num?)?.toDouble(),
      userConfirmed: json['user_confirmed'] == true,
    );
  }
}

/// Per-type counts of distinct entities, for the home overview.
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

/// A capture where an entity appears.
class EntityCapture {
  const EntityCapture({
    required this.id,
    required this.snippet,
    required this.isVoice,
    required this.createdAt,
  });

  final String id;
  final String snippet;
  final bool isVoice;
  final DateTime createdAt;

  factory EntityCapture.fromJson(Map<String, dynamic> json) => EntityCapture(
        id: json['id'] as String,
        snippet: json['snippet'] as String? ?? '',
        isVoice: json['modality'] == 'voice',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// A task linked to an entity.
class EntityTask {
  const EntityTask({
    required this.id,
    required this.title,
    required this.done,
    this.dueAt,
  });

  final String id;
  final String? title;
  final bool done;
  final DateTime? dueAt;

  factory EntityTask.fromJson(Map<String, dynamic> json) => EntityTask(
        id: json['id'] as String,
        title: json['title'] as String?,
        done: json['done'] == true,
        dueAt: json['due_at'] != null
            ? DateTime.tryParse(json['due_at'] as String)
            : null,
      );
}

/// `GET /v1/graph/nodes/:id`: one entity with its context.
class EntityDetail {
  const EntityDetail({
    required this.node,
    required this.firstSeenAt,
    required this.userEdited,
    required this.captures,
    required this.related,
    required this.tasks,
  });

  /// The entity itself; [GraphNode.mentions] counts every mention.
  final GraphNode node;
  final DateTime firstSeenAt;
  final bool userEdited;
  final List<EntityCapture> captures;
  final List<GraphNode> related;
  final List<EntityTask> tasks;

  factory EntityDetail.fromJson(Map<String, dynamic> json) {
    List<dynamic> list(String key) => json[key] as List<dynamic>? ?? const [];
    return EntityDetail(
      node: GraphNode(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
        createdAt: DateTime.parse(json['last_seen_at'] as String),
        mentions: (json['mentions'] as num?)?.toInt() ?? 1,
      ),
      firstSeenAt: DateTime.parse(json['first_seen_at'] as String),
      userEdited: json['user_edited'] == true,
      captures: list('captures')
          .map((e) => EntityCapture.fromJson(e as Map<String, dynamic>))
          .toList(),
      related: list('related')
          .map((e) => _relatedNode(e as Map<String, dynamic>))
          .toList(),
      tasks: list('tasks')
          .map((e) => EntityTask.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // Related entities carry no dates; reuse GraphNode for its label/style.
  static GraphNode _relatedNode(Map<String, dynamic> json) => GraphNode(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        mentions: (json['mentions'] as num?)?.toInt() ?? 1,
      );
}

/// Node types grouped by name across captures (same set as the API).
const groupedNodeTypes = {'person', 'project', 'event', 'topic', 'decision'};
