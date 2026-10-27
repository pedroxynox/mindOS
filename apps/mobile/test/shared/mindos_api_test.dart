import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mindos/src/features/auth/data/auth_api_client.dart';
import 'package:mindos/src/features/auth/data/auth_session.dart';
import 'package:mindos/src/features/auth/data/token_store.dart';
import 'package:mindos/src/features/shared/mindos_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

// The single authenticated client (D-016): transparent refresh-and-retry on
// 401, friendly error mapping, and the session rules of AuthSession
// (single-flight refresh; sign out only on a definitive rejection).
void main() {
  group('MindosApi', () {
    test('refreshes once on 401 and retries with the new token', () async {
      final seen = <String?>[];
      final client = MockClient((req) async {
        seen.add(req.headers['authorization']);
        if (req.headers['authorization'] == 'Bearer access-1') {
          return http.Response('{"message":"expired"}', 401);
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final tokens = FakeTokens();
      final api = MindosApi(tokens: tokens, client: client);

      final res = await api.get('/tasks');

      expect(res, {'ok': true});
      expect(tokens.refreshCalls, 1);
      expect(seen, ['Bearer access-1', 'Bearer access-2']);
    });

    test('surfaces 401 when the refresh is rejected', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final tokens = FakeTokens(refreshSucceeds: false);
      final api = MindosApi(tokens: tokens, client: client);

      await expectLater(
        api.get('/tasks'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 401)),
      );
      expect(tokens.refreshCalls, 1);
    });

    test('maps 503 to the "waking up" message and exposes the API code', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'code': 'query_unavailable', 'message': 'x'}),
            503,
          ));
      final api = MindosApi(tokens: FakeTokens(), client: client);

      await expectLater(
        api.post('/query', {'question': 'hola'}),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'query_unavailable')
            .having((e) => e.message, 'message', contains('despertando'))),
      );
    });

    test('a network failure becomes a friendly ApiException', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final api = MindosApi(tokens: FakeTokens(), client: client);
      await expectLater(api.get('/tasks'), throwsA(isA<ApiException>()));
    });

    test('DELETE with an empty 204 body returns null', () async {
      final client = MockClient((req) async {
        expect(req.method, 'DELETE');
        return http.Response('', 204);
      });
      final api = MindosApi(tokens: FakeTokens(), client: client);
      expect(await api.delete('/tasks/1'), isNull);
    });
  });

  group('AuthSession', () {
    late TokenStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'mindos.auth.access': 'old-access',
        'mindos.auth.refresh': 'refresh-1',
      });
      store = TokenStore(await SharedPreferences.getInstance());
    });

    test('concurrent refreshes share ONE request (single-use token)', () async {
      var calls = 0;
      final gate = Completer<void>();
      final api = _FakeAuthApi(onRefresh: (token) async {
        calls++;
        await gate.future;
        return const AuthTokens(
            accessToken: 'new-access', refreshToken: 'refresh-2', expiresIn: 3600);
      });
      var expired = 0;
      final session =
          AuthSession(store: store, api: api, onExpired: () => expired++);

      final a = session.refresh();
      final b = session.refresh();
      gate.complete();

      expect(await a, isTrue);
      expect(await b, isTrue);
      expect(calls, 1);
      expect(store.accessToken, 'new-access');
      expect(store.refreshToken, 'refresh-2');
      expect(expired, 0);
    });

    test('signs out when the server rejects the refresh token', () async {
      final api = _FakeAuthApi(
          onRefresh: (_) async => throw const AuthException('no', 401));
      var expired = 0;
      final session =
          AuthSession(store: store, api: api, onExpired: () => expired++);

      expect(await session.refresh(), isFalse);
      expect(expired, 1);
    });

    test('keeps the session on a network failure', () async {
      final api =
          _FakeAuthApi(onRefresh: (_) async => throw const AuthException('net'));
      var expired = 0;
      final session =
          AuthSession(store: store, api: api, onExpired: () => expired++);

      expect(await session.refresh(), isFalse);
      expect(expired, 0);
    });
  });
}

class _FakeAuthApi extends AuthApiClient {
  _FakeAuthApi({required this.onRefresh});

  final Future<AuthTokens> Function(String token) onRefresh;

  @override
  Future<AuthTokens> refresh(String refreshToken) => onRefresh(refreshToken);
}
