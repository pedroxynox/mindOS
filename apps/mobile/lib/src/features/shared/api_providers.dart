import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'mindos_api.dart';

/// Shared authenticated API client, wired to the current session token.
final mindosApiProvider = Provider<MindosApi>((ref) {
  final store = ref.watch(tokenStoreProvider);
  return MindosApi(tokenProvider: () async => store.accessToken);
});
