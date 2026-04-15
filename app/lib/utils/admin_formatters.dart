import 'package:intl/intl.dart';

class AdminFormatters {
  AdminFormatters._();

  static final NumberFormat _countFormat = NumberFormat.decimalPattern('en_US');
  static final NumberFormat _compactCountFormat = NumberFormat.compact(locale: 'en_US');
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );
  static final DateFormat _dateYmdFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _dateYmdHmFormat = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _monthYearFormat = DateFormat('MMMM yyyy');
  static final DateFormat _monthAbbrevFormat = DateFormat('MMM');
  static final DateFormat _monthKeyFormat = DateFormat('yyyy_MM');

  static String currency(num value, {int decimalDigits = 2}) {
    if (decimalDigits == 2) return _currencyFormat.format(value);
    return NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: decimalDigits,
    ).format(value);
  }

  static String decimal(num value, {int digits = 2}) {
    return NumberFormat.decimalPatternDigits(locale: 'en_US', decimalDigits: digits).format(value);
  }

  static String count(num value) => _countFormat.format(value);

  static String compactCount(num value) => _compactCountFormat.format(value);

  static String percent(double value, {int digits = 1, bool inputIsFraction = true}) {
    final normalized = inputIsFraction ? value : value / 100;
    return NumberFormat.decimalPercentPattern(locale: 'en_US', decimalDigits: digits).format(normalized);
  }

  static String dateYmd(DateTime value) => _dateYmdFormat.format(value.toLocal());

  static String dateYmdHm(DateTime value) => _dateYmdHmFormat.format(value.toLocal());

  static String monthYear(DateTime value) => _monthYearFormat.format(value.toLocal());

  static String monthAbbrev(DateTime value) => _monthAbbrevFormat.format(value.toLocal());

  static String monthKey(DateTime value) => _monthKeyFormat.format(value.toLocal());
}

