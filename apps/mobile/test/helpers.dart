import 'package:mindos/src/features/auth/data/auth_session.dart';
import 'package:mindos/src/features/feedback/feedback_api.dart';
import 'package:mindos/src/features/shared/mindos_api.dart';

/// A [TokenSource] for tests: a fixed token and a scripted refresh outcome.
class FakeTokens implements TokenSource {
  FakeTokens({this.token = 'access-1', this.refreshSucceeds = true});

  String? token;
  bool refreshSucceeds;
  int refreshCalls = 0;

  @override
  String? get accessToken => token;

  @override
  Future<bool> refresh() async {
    refreshCalls++;
    if (refreshSucceeds) token = 'access-${refreshCalls + 1}';
    return refreshSucceeds;
  }
}

/// A [MindosApi] that is never meant to hit the network (feature fakes
/// override every method they use).
MindosApi offlineApi() => MindosApi(tokens: FakeTokens());

/// Records 👍/👎 votes instead of calling the API.
class FakeFeedbackApi extends FeedbackApi {
  FakeFeedbackApi({this.fail = false, this.initial}) : super(offlineApi());

  final bool fail;
  final bool? initial;
  final votes = <(FeedbackTarget, bool)>[];

  @override
  Future<void> vote(FeedbackTarget target, {required bool useful}) async {
    if (fail) throw const ApiException('No se pudo conectar con el servidor.');
    votes.add((target, useful));
  }

  @override
  Future<bool?> current(FeedbackTarget target) async => initial;
}
