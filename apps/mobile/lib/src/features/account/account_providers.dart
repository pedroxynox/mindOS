import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../auth/auth_providers.dart';
import '../shared/api_providers.dart';
import 'data/me_api.dart';
import 'locale_defaults.dart';

final meApiProvider = Provider<MeApi>((ref) => MeApi(ref.watch(mindosApiProvider)));

/// Reads the device's IANA timezone (overridable in tests).
final deviceTimeZoneProvider = Provider<Future<String?> Function()>((ref) {
  return () async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return null;
    }
  };
});

/// Device country code from the platform locale (may be null on the web).
final deviceCountryProvider = Provider<String? Function()>((ref) {
  return () => ui.PlatformDispatcher.instance.locale.countryCode;
});

/// The signed-in user's profile, kept in sync with the device: on first read it
/// sends the device timezone if it changed, and proposes a currency from the
/// locale/zone when none is chosen yet (D-013 / D-014). Never throws for a
/// sync problem — the app keeps working with what the server has.
final meProvider = FutureProvider<Me>((ref) async {
  // Re-run for every new session (login / logout / another account).
  ref.watch(authControllerProvider.select((s) => s.status));
  final api = ref.watch(meApiProvider);
  var me = await api.get();
  try {
    final zone = await ref.read(deviceTimeZoneProvider)();
    final needsZone = zone != null && zone.isNotEmpty && zone != me.timezone;
    final suggested = me.currency == null
        ? suggestCurrency(
            countryCode: ref.read(deviceCountryProvider)(),
            timeZone: zone ?? me.timezone,
          )
        : null;
    if (needsZone || suggested != null) {
      me = await api.update(
        timezone: needsZone ? zone : null,
        currency: suggested,
      );
    }
  } catch (_) {
    // Keep the server's view; the sync is retried on the next app start.
  }
  return me;
});

/// Await the settings sync before computing anything day- or money-based, so
/// the first screen after a timezone change is already correct. Errors are
/// swallowed: the server falls back to what it has stored.
Future<void> settingsReady(Ref ref) async {
  try {
    await ref.watch(meProvider.future);
  } catch (_) {}
}

/// The currency money is shown in (USD until the profile loads).
final displayCurrencyProvider = Provider<String>((ref) {
  return ref.watch(meProvider).valueOrNull?.effectiveCurrency ?? 'USD';
});
