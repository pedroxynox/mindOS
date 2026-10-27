import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mindos/src/features/feedback/feedback_api.dart';
import 'package:mindos/src/features/graph/data/graph_api_client.dart';
import 'package:mindos/src/features/shared/mindos_api.dart';

import '../helpers.dart';

// The wire contract of the corrections and feedback calls (FR-2.4 / FR-3.5):
// method, path, scope and body, and the parsing of the entity card.
void main() {
  late List<http.Request> sent;
  late Object? Function(http.Request) reply;

  MindosApi api() => MindosApi(
        tokens: FakeTokens(),
        client: MockClient((req) async {
          sent.add(req);
          final body = reply(req);
          return http.Response(body == null ? '' : jsonEncode(body), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

  setUp(() {
    sent = [];
    reply = (_) => null;
  });

  test('renames one mention or the whole entity', () async {
    reply = (_) => {'updated': 3};
    final client = GraphApiClient(api());

    expect(await client.renameNode('n1', 'Marcos'), 3);
    await client.renameNode('n1', 'Marcos', wholeEntity: true);

    expect(sent.map((r) => r.method), ['PATCH', 'PATCH']);
    expect(sent.first.url.path, endsWith('/graph/nodes/n1'));
    expect(jsonDecode(sent.first.body), {'title': 'Marcos', 'scope': 'node'});
    expect(jsonDecode(sent.last.body)['scope'], 'entity');
  });

  test('removes with the scope in the query and reviews connections', () async {
    final client = GraphApiClient(api());

    await client.removeNode('n1', wholeEntity: true);
    await client.reviewEdge('e1', confirmed: false);

    expect(sent.first.method, 'DELETE');
    expect(sent.first.url.path, endsWith('/graph/nodes/n1'));
    expect(sent.first.url.queryParameters, {'scope': 'entity'});
    expect(sent.last.url.path, endsWith('/graph/edges/e1'));
    expect(jsonDecode(sent.last.body), {'confirmed': false});
  });

  test('parses the entity card', () async {
    reply = (_) => {
          'id': 'm1',
          'type': 'person',
          'title': 'Marcos',
          'mentions': 3,
          'node_ids': ['m1', 'm2', 'm3'],
          'confidence': 0.9,
          'user_edited': true,
          'first_seen_at': '2026-10-01T10:00:00.000Z',
          'last_seen_at': '2026-10-20T10:00:00.000Z',
          'captures': [
            {
              'id': 'c1',
              'snippet': 'Llamar a Marcos',
              'modality': 'voice',
              'occurred_at': null,
              'created_at': '2026-10-20T10:00:00.000Z',
            },
          ],
          'related': [
            {'id': 'p1', 'type': 'project', 'title': 'Aurora', 'mentions': 2},
          ],
          'tasks': [
            {
              'id': 't1',
              'title': 'Llamar a Marcos',
              'done': false,
              'priority': 'high',
              'due_at': '2026-10-28T12:00:00.000Z',
            },
          ],
        };

    final detail = await GraphApiClient(api()).entity('m1');

    expect(detail.node.label, 'Marcos');
    expect(detail.node.mentions, 3);
    expect(detail.userEdited, isTrue);
    expect(detail.captures.single.isVoice, isTrue);
    expect(detail.related.single.label, 'Aurora');
    expect(detail.related.single.mentions, 2);
    expect(detail.tasks.single.dueAt, isNotNull);
  });

  test('feedback votes and reads the current vote', () async {
    reply = (req) => req.method == 'GET' ? {'useful': false} : {'id': 'f1'};
    final feedback = FeedbackApi(api());
    const target = FeedbackTarget.query('¿Qué tengo pendiente?');

    await feedback.vote(target, useful: true);
    final current = await feedback.current(target);

    expect(jsonDecode(sent.first.body), {
      'target_type': 'query',
      'target_id': '¿Qué tengo pendiente?',
      'useful': true,
    });
    expect(sent.last.url.queryParameters, {
      'target_type': 'query',
      'target_id': '¿Qué tengo pendiente?',
    });
    expect(current, isFalse);
  });
}
