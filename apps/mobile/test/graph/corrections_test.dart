import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mindos/src/features/feedback/feedback_api.dart';
import 'package:mindos/src/features/graph/data/graph_api_client.dart';
import 'package:mindos/src/features/graph/data/graph_models.dart';
import 'package:mindos/src/features/graph/graph_providers.dart';
import 'package:mindos/src/features/graph/presentation/capture_insights_screen.dart';
import 'package:mindos/src/features/graph/presentation/entity_screen.dart';
import 'package:mindos/src/features/graph/presentation/nodes_list_screen.dart';
import 'package:mindos/src/theme.dart';

import '../helpers.dart';

/// A graph backend in memory that records every correction.
class _FakeGraph extends GraphApiClient {
  _FakeGraph() : super(offlineApi());

  final renamed = <(String, String, bool)>[];
  final removed = <(String, bool)>[];
  final reviewed = <(String, bool)>[];

  final _created = DateTime.utc(2026, 10, 20, 10);

  late List<GraphNode> nodes = [
    GraphNode(id: 't1', type: 'task', title: 'Llamar a Marcos', createdAt: _created),
    GraphNode(id: 'p1', type: 'person', title: 'Marcos', createdAt: _created),
  ];
  late List<GraphEdge> edges = const [
    GraphEdge(id: 'e1', source: 't1', target: 'p1', type: 'assigned_to'),
  ];

  @override
  Future<CaptureEntities> captureEntities(String captureId) async =>
      CaptureEntities(
        captureId: captureId,
        status: 'processed',
        nodes: nodes,
        edges: edges,
      );

  @override
  Future<EntityDetail> entity(String id) async => EntityDetail(
        node: GraphNode(
          id: id,
          type: 'person',
          title: nodes.firstWhere((n) => n.id == 'p1').title,
          createdAt: _created,
          mentions: 3,
        ),
        firstSeenAt: DateTime.utc(2026, 10, 1, 10),
        userEdited: false,
        captures: [
          EntityCapture(
            id: 'c1',
            snippet: 'Llamar a Marcos por el presupuesto',
            isVoice: true,
            createdAt: _created,
          ),
        ],
        related: [
          GraphNode(
            id: 'pr1',
            type: 'project',
            title: 'Aurora',
            createdAt: _created,
            mentions: 2,
          ),
        ],
        tasks: const [
          EntityTask(id: 't1', title: 'Llamar a Marcos', done: false),
        ],
      );

  @override
  Future<GraphNodePage> listNodes(String type,
          {String? cursor, int limit = 50}) async =>
      GraphNodePage(data: [
        GraphNode(
          id: 'p1',
          type: 'person',
          title: 'Marcos',
          createdAt: _created,
          mentions: 3,
        ),
        GraphNode(id: 'p2', type: 'person', title: 'Ana', createdAt: _created),
      ]);

  @override
  Future<int> renameNode(String id, String title,
      {bool wholeEntity = false}) async {
    renamed.add((id, title, wholeEntity));
    nodes = [
      for (final n in nodes)
        n.id == id
            ? GraphNode(id: n.id, type: n.type, title: title, createdAt: n.createdAt)
            : n,
    ];
    return wholeEntity ? 3 : 1;
  }

  @override
  Future<void> removeNode(String id, {bool wholeEntity = false}) async {
    removed.add((id, wholeEntity));
    nodes = nodes.where((n) => n.id != id).toList();
    edges = edges.where((e) => e.source != id && e.target != id).toList();
  }

  @override
  Future<void> reviewEdge(String id, {required bool confirmed}) async {
    reviewed.add((id, confirmed));
    edges = confirmed
        ? [
            for (final e in edges)
              GraphEdge(
                id: e.id,
                source: e.source,
                target: e.target,
                type: e.type,
                userConfirmed: e.id == id || e.userConfirmed,
              ),
          ]
        : edges.where((e) => e.id != id).toList();
  }
}

// "Lo que entendí" and the entity card (FR-2.4 / FR-3.5): rate the capture,
// fix a name, remove what was wrong, confirm or reject a connection; rename
// or forget an entity everywhere. The graph backend is an in-memory fake.
void main() {
  Future<(_FakeGraph, FakeFeedbackApi)> pump(
    WidgetTester tester,
    Widget home, {
    String? location,
  }) async {
    final graph = _FakeGraph();
    final feedback = FakeFeedbackApi();
    final app = location == null
        ? MaterialApp(theme: AppTheme.dark(), home: home)
        : MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: GoRouter(
              initialLocation: location,
              routes: [
                GoRoute(path: '/', builder: (_, __) => const Text('Hoy')),
                GoRoute(path: '/node/:id', builder: (_, __) => home),
              ],
            ),
          );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        graphApiClientProvider.overrideWithValue(graph),
        feedbackApiProvider.overrideWithValue(feedback),
      ],
      child: app,
    ));
    await tester.pumpAndSettle();
    return (graph, feedback);
  }

  group('Lo que entendí', () {
    const screen = CaptureInsightsScreen(captureId: 'c1');

    testWidgets('records a 👎 on the capture and points at the fixes',
        (tester) async {
      final (_, feedback) = await pump(tester, screen);

      expect(find.text('¿Lo entendí bien?'), findsOneWidget);
      await tester.tap(find.byTooltip('No me sirvió'));
      await tester.pumpAndSettle();

      expect(feedback.votes, [(const FeedbackTarget.capture('c1'), false)]);
      expect(find.text('Gracias. Si algo falló, corrígelo abajo.'), findsOneWidget);
    });

    testWidgets('confirms a connection', (tester) async {
      final (graph, _) = await pump(tester, screen);

      await tester.tap(find.byTooltip('Es correcto'));
      await tester.pumpAndSettle();

      expect(graph.reviewed, [('e1', true)]);
      expect(find.byTooltip('Confirmada por ti'), findsOneWidget);
      expect(find.text('Conexión confirmada.'), findsOneWidget);
    });

    testWidgets('fixes a name in this capture only', (tester) async {
      final (graph, _) = await pump(tester, screen);

      await tester.tap(find.text('Llamar a Marcos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Corregir nombre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Llamar a Marcos el lunes');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(graph.renamed, [('t1', 'Llamar a Marcos el lunes', false)]);
      expect(find.text('Llamar a Marcos el lunes'), findsOneWidget);
    });

    testWidgets('removes a wrong item after confirming', (tester) async {
      final (graph, _) = await pump(tester, screen);

      await tester.tap(find.text('Marcos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar'));
      await tester.pumpAndSettle();
      expect(find.text('¿Quitar «Marcos»?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Quitar'));
      await tester.pumpAndSettle();

      expect(graph.removed, [('p1', false)]);
      expect(find.text('Marcos'), findsNothing);
      expect(find.text('Conexiones'), findsNothing);
      expect(find.text('Quitado.'), findsOneWidget);
    });

    testWidgets('cancelling the removal changes nothing', (tester) async {
      final (graph, _) = await pump(tester, screen);

      await tester.tap(find.text('Marcos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(graph.removed, isEmpty);
      expect(find.text('Marcos'), findsOneWidget);
    });
  });

  group('Ficha de entidad', () {
    const screen = EntityScreen(nodeId: 'p1');

    testWidgets('shows mentions, tasks, related and captures', (tester) async {
      await pump(tester, screen, location: '/node/p1');

      expect(find.text('Marcos'), findsOneWidget);
      expect(find.textContaining('Lo mencionaste 3 veces'), findsOneWidget);
      expect(find.text('Llamar a Marcos'), findsOneWidget);
      expect(find.text('Aurora · 2'), findsOneWidget);
      expect(find.text('Llamar a Marcos por el presupuesto'), findsOneWidget);
    });

    testWidgets('renames the entity everywhere', (tester) async {
      final (graph, _) = await pump(tester, screen, location: '/node/p1');

      await tester.tap(find.byTooltip('Renombrar'));
      await tester.pumpAndSettle();
      expect(find.text('Cambia en las 3 menciones.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Marcos Pérez');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(graph.renamed, [('p1', 'Marcos Pérez', true)]);
      expect(find.text('Marcos Pérez'), findsOneWidget);
    });

    testWidgets('forgets the entity and leaves the card', (tester) async {
      final (graph, _) = await pump(tester, screen, location: '/node/p1');

      await tester.tap(find.byTooltip('Olvidar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('tus 3 capturas'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Olvidar'));
      await tester.pumpAndSettle();

      expect(graph.removed, [('p1', true)]);
      expect(find.text('Hoy'), findsOneWidget);
    });
  });

  testWidgets('lists people grouped with their mentions', (tester) async {
    await pump(tester, const NodesListScreen(type: 'person'));

    expect(find.text('Marcos'), findsOneWidget);
    expect(find.text('3 menciones'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('1 mención'), findsNothing);
  });
}
