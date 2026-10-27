// Sensible defaults for a LatAm-first user base (D-014): which currency to
// propose before the user picks one. Country (from the device locale) wins;
// when the browser only says "es" we fall back to the device timezone.

/// Currencies offered in the picker (most relevant first).
const supportedCurrencies = <String, String>{
  'MXN': 'Peso mexicano',
  'BRL': 'Real brasileño',
  'COP': 'Peso colombiano',
  'ARS': 'Peso argentino',
  'CLP': 'Peso chileno',
  'PEN': 'Sol peruano',
  'UYU': 'Peso uruguayo',
  'USD': 'Dólar estadounidense',
  'EUR': 'Euro',
  'GTQ': 'Quetzal',
  'CRC': 'Colón costarricense',
  'DOP': 'Peso dominicano',
  'BOB': 'Boliviano',
  'PYG': 'Guaraní',
};

const _byCountry = <String, String>{
  'MX': 'MXN', 'BR': 'BRL', 'CO': 'COP', 'AR': 'ARS', 'CL': 'CLP',
  'PE': 'PEN', 'UY': 'UYU', 'US': 'USD', 'EC': 'USD', 'SV': 'USD',
  'PA': 'USD', 'PR': 'USD', 'GT': 'GTQ', 'CR': 'CRC', 'DO': 'DOP',
  'BO': 'BOB', 'PY': 'PYG', 'ES': 'EUR', 'PT': 'EUR', 'FR': 'EUR',
  'DE': 'EUR', 'IT': 'EUR',
};

const _byZone = <String, String>{
  'America/Mexico_City': 'MXN', 'America/Monterrey': 'MXN',
  'America/Tijuana': 'MXN', 'America/Cancun': 'MXN',
  'America/Merida': 'MXN', 'America/Chihuahua': 'MXN',
  'America/Hermosillo': 'MXN', 'America/Mazatlan': 'MXN',
  'America/Sao_Paulo': 'BRL', 'America/Manaus': 'BRL',
  'America/Fortaleza': 'BRL', 'America/Recife': 'BRL',
  'America/Bahia': 'BRL', 'America/Belem': 'BRL',
  'America/Bogota': 'COP', 'America/Santiago': 'CLP', 'America/Lima': 'PEN',
  'America/Montevideo': 'UYU', 'America/Guatemala': 'GTQ',
  'America/Costa_Rica': 'CRC', 'America/Santo_Domingo': 'DOP',
  'America/La_Paz': 'BOB', 'America/Asuncion': 'PYG',
  'America/Guayaquil': 'USD', 'America/El_Salvador': 'USD',
  'America/Panama': 'USD', 'Europe/Madrid': 'EUR', 'Europe/Lisbon': 'EUR',
};

/// Propose a currency from the device's country code and/or IANA zone.
String suggestCurrency({String? countryCode, String? timeZone}) {
  final byCountry = _byCountry[countryCode?.toUpperCase()];
  if (byCountry != null) return byCountry;
  if (timeZone != null) {
    final byZone = _byZone[timeZone];
    if (byZone != null) return byZone;
    if (timeZone.startsWith('America/Argentina/')) return 'ARS';
  }
  return 'USD';
}

/// Currencies conventionally shown without decimals.
const _zeroDecimal = {'CLP', 'COP', 'PYG', 'ARS'};

const _symbols = <String, String>{
  'USD': 'US\$', 'MXN': '\$', 'BRL': 'R\$', 'COP': '\$', 'ARS': '\$',
  'CLP': '\$', 'PEN': 'S/', 'UYU': '\$U', 'EUR': '€', 'GTQ': 'Q',
  'CRC': '₡', 'DOP': 'RD\$', 'BOB': 'Bs', 'PYG': '₲', 'GBP': '£',
};

/// Short symbol for a currency (falls back to the ISO code).
String currencySymbol(String code) => _symbols[code] ?? code;

/// "R$ 1.234,50" / "$ 1.235" / "US$ 12.30" — dependency-free money format.
/// Uses the Latin-American convention (dot thousands, comma decimals) except
/// for USD, which uses the US one.
String formatMoney(num amount, String currency) {
  final decimals = _zeroDecimal.contains(currency) ? 0 : 2;
  final usStyle = currency == 'USD';
  final fixed = amount.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(usStyle ? ',' : '.');
    buf.write(intPart[i]);
  }
  final frac = decimals > 0 ? '${usStyle ? '.' : ','}${parts[1]}' : '';
  final sign = amount < 0 ? '-' : '';
  return '$sign${currencySymbol(currency)} $buf$frac';
}
