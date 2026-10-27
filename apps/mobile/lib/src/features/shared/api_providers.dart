import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'mindos_api.dart';

/// The single authenticated API client, wired to the session token source
/// (transparent refresh on 401).
final mindosApiProvider = Provider<MindosApi>((ref) {
  return MindosApi(tokens: ref.watch(tokenSourceProvider));
});
