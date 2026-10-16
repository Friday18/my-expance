/// Money formatting without locale surprises. INR uses Indian grouping (1,25,000).

const Map<String, String> _symbols = {
  'INR': '₹',
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'JPY': '¥',
  'AED': 'AED ',
  'SGD': r'S$',
  'AUD': r'A$',
  'CAD': r'C$',
};

String currencySymbol(String currency) => _symbols[currency] ?? '$currency ';

String _groupDigits(String digits, {required bool indian}) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groupSize = indian ? 2 : 3;
  final parts = <String>[];
  while (rest.length > groupSize) {
    parts.insert(0, rest.substring(rest.length - groupSize));
    rest = rest.substring(0, rest.length - groupSize);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// formatMoney(125000) == '₹1,25,000'; formatMoney(99.5) == '₹99.50'.
/// Decimals are shown only when the amount has paise/cents, unless [decimals] forces them.
String formatMoney(double value, {String currency = 'INR', bool? decimals}) {
  final negative = value < 0;
  final cents = (value.abs() * 100).round();
  final frac = cents % 100;
  final showDecimals = decimals ?? frac != 0;
  final whole = showDecimals ? cents ~/ 100 : value.abs().round();
  final grouped = _groupDigits(whole.toString(), indian: currency == 'INR');
  final body = showDecimals ? '$grouped.${frac.toString().padLeft(2, '0')}' : grouped;
  return '${negative ? '-' : ''}${currencySymbol(currency)}$body';
}

/// Short form for chart labels: ₹950, ₹1.2k, ₹3.4L, ₹1.1Cr (INR) or $1.2k, $3.4M.
String formatCompact(double value, {String currency = 'INR'}) {
  final sym = currencySymbol(currency);
  final v = value.abs();
  final sign = value < 0 ? '-' : '';
  String trim(double x) {
    final s = x.toStringAsFixed(x >= 10 ? 0 : 1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  if (currency == 'INR') {
    if (v >= 1e7) return '$sign$sym${trim(v / 1e7)}Cr';
    if (v >= 1e5) return '$sign$sym${trim(v / 1e5)}L';
  } else {
    if (v >= 1e9) return '$sign$sym${trim(v / 1e9)}B';
    if (v >= 1e6) return '$sign$sym${trim(v / 1e6)}M';
  }
  if (v >= 1e3) return '$sign$sym${trim(v / 1e3)}k';
  return '$sign$sym${v.round()}';
}
