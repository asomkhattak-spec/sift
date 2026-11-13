import 'dart:convert';
import 'dart:math' as math;

import '../models/search_models.dart';
import '../services/http_service.dart';
import '../utils/text_utils.dart';

/// Resolves small, self-contained questions before or alongside web results.
/// Every answer names its source; none is scraped from a search result page.
class InstantAnswerEngine {
  InstantAnswerEngine(this._http);

  final SiftHttpBase _http;

  Future<InstantAnswer?> resolve(String raw, {bool allowNetwork = true}) async {
    final query = normalizeQuery(raw);
    if (query.isEmpty) return null;

    final calculation = _calculate(query);
    if (calculation != null) return calculation;

    final conversion = _parseConversion(query);
    if (conversion != null) {
      if (conversion.isCurrency) {
        if (!allowNetwork) return null;
        try {
          return await _convertCurrency(conversion);
        } catch (_) {
          return null;
        }
      }
      return _convertUnit(conversion);
    }

    if (!allowNetwork) return null;

    final city = _weatherCity(query);
    if (city != null) {
      try {
        return await _weather(city, tomorrow: _asksTomorrow(query));
      } catch (_) {
        return null;
      }
    }

    final word = _dictionaryWord(query);
    if (word != null) {
      try {
        return await _dictionary(word);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /* ------------------------------------------------------------------------
   * Arithmetic
   * ---------------------------------------------------------------------- */

  InstantAnswer? _calculate(String raw) {
    var expression = raw.toLowerCase().trim();
    if (expression.endsWith('?')) {
      expression = expression.substring(0, expression.length - 1).trim();
    }
    if (expression.endsWith('=')) {
      expression = expression.substring(0, expression.length - 1).trim();
    }
    for (final prefix in const [
      'what is ',
      "what's ",
      'calculate ',
      'compute ',
      'evaluate ',
      'solve ',
      'calc ',
    ]) {
      if (expression.startsWith(prefix)) {
        expression = expression.substring(prefix.length).trim();
        break;
      }
    }
    if (expression.isEmpty || expression.length > 90) return null;

    final percentOf = RegExp(
      r'^([0-9]+(?:\.[0-9]+)?)\s*%\s*of\s*([0-9]+(?:\.[0-9]+)?)$',
    ).firstMatch(expression);
    if (percentOf != null) {
      final percent = double.parse(percentOf.group(1)!);
      final total = double.parse(percentOf.group(2)!);
      final value = percent / 100 * total;
      return _calculatorAnswer(expression, value, '$percent% of $total');
    }

    final hasDigit = RegExp(r'[0-9]').hasMatch(expression);
    final hasFunction =
        RegExp(r'\b(sqrt|sin|cos|tan|log|ln|abs|round|floor|ceil)\s*\(')
            .hasMatch(expression);
    final hasOperator = RegExp(r'[+\-*/^%]').hasMatch(expression);
    if ((!hasDigit && !hasFunction) || !hasOperator) return null;
    if (RegExp(r'\b(to|in|into|define|weather|forecast|meaning|versus|vs)\b')
        .hasMatch(expression)) {
      return null;
    }
    if (!RegExp(r'^[0-9a-z\s.,+\-*/^%()]+$').hasMatch(expression)) return null;

    try {
      final value = _MathParser(expression.replaceAll(',', '')).parse();
      if (!value.isFinite) return null;
      return _calculatorAnswer(expression, value, expression);
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  InstantAnswer _calculatorAnswer(
    String expression,
    double value,
    String label,
  ) {
    final result = _formatNumber(value);
    return InstantAnswer(
      kind: 'calculator',
      title: result,
      subtitle: 'Calculator',
      body: 'Evaluated on this device. No network request was made.',
      facts: [
        AnswerFact('Expression', label),
        AnswerFact('Result', result),
      ],
      source: 'Sift · on-device',
    );
  }

  /* ------------------------------------------------------------------------
   * Units and currency
   * ---------------------------------------------------------------------- */

  _Conversion? _parseConversion(String raw) {
    var query = raw.toLowerCase().trim();
    while (query.endsWith('?') || query.endsWith('.')) {
      query = query.substring(0, query.length - 1).trim();
    }
    for (final prefix in const [
      'convert ',
      'what is ',
      "what's ",
      'how much is ',
      'calculate ',
    ]) {
      if (query.startsWith(prefix)) {
        query = query.substring(prefix.length).trim();
        break;
      }
    }

    final direct = RegExp(
      r'^([0-9][0-9.,]*)?\s*([a-z°][a-z0-9°/ .\-]*?)\s+(?:to|in|into)\s+([a-z°][a-z0-9°/ .\-]*)$',
    ).firstMatch(query);
    if (direct != null) {
      final amount = _parseAmount(direct.group(1));
      final from = direct.group(2)!.trim();
      final to = direct.group(3)!.trim();
      if (amount != null && from.isNotEmpty && to.isNotEmpty) {
        return _buildConversion(amount, from, to);
      }
    }

    final currencyOnly = RegExp(r'^([a-z]{3})\s+(?:to|in|into)\s+([a-z]{3})$')
        .firstMatch(query);
    if (currencyOnly != null) {
      final from = currencyOnly.group(1)!;
      final to = currencyOnly.group(2)!;
      if (_currencies.containsKey(from) && _currencies.containsKey(to)) {
        return _Conversion(
          amount: 1,
          from: from,
          to: to,
          isCurrency: true,
        );
      }
    }

    final howMany = RegExp(
      r'^how many\s+([a-z°][a-z0-9° ./\-]*?)\s+(?:in|are in)\s+([0-9][0-9.,]*)\s+([a-z°][a-z0-9° ./\-]*)$',
    ).firstMatch(query);
    if (howMany != null) {
      final amount = _parseAmount(howMany.group(2));
      if (amount != null) {
        return _buildConversion(amount, howMany.group(3)!.trim(), howMany.group(1)!.trim());
      }
    }
    return null;
  }

  _Conversion? _buildConversion(double amount, String fromUnit, String toUnit) {
    final from = _unitFor(fromUnit);
    final to = _unitFor(toUnit);
    if (from != null && to != null) {
      if (from.dimension != to.dimension) return null;
      return _Conversion(amount: amount, from: from.key, to: to.key);
    }
    final fromCurrency = _currencies.containsKey(fromUnit);
    final toCurrency = _currencies.containsKey(toUnit);
    if (fromCurrency && toCurrency) {
      return _Conversion(
        amount: amount,
        from: fromUnit,
        to: toUnit,
        isCurrency: true,
      );
    }
    return null;
  }

  double? _parseAmount(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 1;
    final parsed = double.tryParse(raw.replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  InstantAnswer _convertUnit(_Conversion conversion) {
    final from = _units[conversion.from]!;
    final to = _units[conversion.to]!;
    final amount = conversion.amount;

    double converted;
    if (from.dimension == 'temperature') {
      final celsius = from.toCelsius(amount);
      converted = to.fromCelsius(celsius);
    } else {
      converted = amount * from.factor / to.factor;
    }

    final result = _formatNumber(converted);
    final input = '${_formatNumber(amount)} ${from.label}';
    final output = '$result ${to.label}';
    final rate = from.dimension == 'temperature'
        ? '${_formatNumber(converted)} ${to.label}'
        : '1 ${from.singular} = ${_formatNumber(from.factor / to.factor)} ${to.label}';

    return InstantAnswer(
      kind: 'conversion',
      title: output,
      subtitle: '$input converted',
      body: 'Converted on this device with standard definitions. '
          'No request was sent.',
      facts: [
        AnswerFact('Input', input),
        AnswerFact('Result', output),
        if (from.dimension != 'temperature') AnswerFact('Rate', rate),
      ],
      source: 'Sift · on-device converter',
    );
  }

  Future<InstantAnswer> _convertCurrency(_Conversion conversion) async {
    final from = conversion.from.toUpperCase();
    final to = conversion.to.toUpperCase();
    final amount = conversion.amount;
    final uri = Uri.https('api.frankfurter.app', '/latest', {
      'amount': _formatNumber(amount),
      'from': from,
      'to': to,
    });
    final data = await _http.getJson(
      uri.toString(),
      timeout: const Duration(seconds: 7),
      cacheSeconds: 1800,
    );
    final rates = data['rates'];
    if (rates is! Map || rates[to] is! num) {
      throw const SiftHttpException('No reference rate for that pair.');
    }
    final converted = (rates[to] as num).toDouble();
    final date = data['date']?.toString();
    final result = _formatNumber(converted);
    return InstantAnswer(
      kind: 'currency',
      title: '$result $to',
      subtitle: '${_formatNumber(amount)} $from · ECB reference rates',
      body: 'Reference rates are published on working days. '
          'Sift does not add a markup or route this through an account.',
      facts: [
        AnswerFact('From', '${_formatNumber(amount)} $from'),
        AnswerFact('To', '$result $to'),
        AnswerFact(
          'Rate',
          '1 $from = ${_formatNumber(converted / amount)} $to',
        ),
        if (date != null) AnswerFact('Reference date', date),
      ],
      link: 'https://www.frankfurter.app/',
      linkLabel: 'Frankfurter',
      source: 'Frankfurter · ECB reference rates',
      isLive: true,
    );
  }

  /* ------------------------------------------------------------------------
   * Weather
   * ---------------------------------------------------------------------- */

  String? _weatherCity(String raw) {
    final query = raw.toLowerCase().trim().replaceAll(RegExp(r'[?!.]+$'), '');
    final patterns = [
      RegExp(r'\bweather(?:\s+(?:like|today|now))?\s+(?:in|for)\s+(.+)$'),
      RegExp(r'\bforecast\s+(?:in|for)\s+(.+)$'),
      RegExp(r'\btemperature\s+(?:in|for)\s+(.+)$'),
      RegExp(r'^(.+?)\s+(?:weather|forecast)(?:\s+today|\s+now)?$'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(query);
      if (match == null) continue;
      var city = match.group(1)?.trim() ?? '';
      city = city
          .replaceAll(RegExp(r'\s+(right now|today|tomorrow|this week)$'), '')
          .trim();
      city = city.replaceFirst(RegExp(r'^the\s+'), '');
      if (city.length >= 2 && city.length <= 80) return city;
    }
    return null;
  }

  bool _asksTomorrow(String raw) => raw.toLowerCase().contains('tomorrow');

  Future<InstantAnswer> _weather(String city, {required bool tomorrow}) async {
    final geoUri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': city,
      'count': '1',
      'language': 'en',
      'format': 'json',
    });
    final geo = await _http.getJson(
      geoUri.toString(),
      timeout: const Duration(seconds: 7),
      cacheSeconds: 86400,
    );
    final results = geo['results'];
    if (results is! List || results.isEmpty) {
      throw const SiftHttpException('Place not found.');
    }
    final place = results.first;
    if (place is! Map) throw const SiftHttpException('Place not found.');
    final latitude = place['latitude'];
    final longitude = place['longitude'];
    if (latitude is! num || longitude is! num) {
      throw const SiftHttpException('Place not found.');
    }
    final name = place['name']?.toString() ?? city;
    final region = place['admin1']?.toString() ?? '';
    final country = place['country']?.toString() ?? '';
    final countryCode = place['country_code']?.toString() ?? '';

    final forecastUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'current':
          'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m',
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset',
      'timezone': 'auto',
      'forecast_days': '2',
    });
    final forecast = await _http.getJson(
      forecastUri.toString(),
      timeout: const Duration(seconds: 8),
      cacheSeconds: 600,
    );
    final current = forecast['current'];
    final daily = forecast['daily'];
    if (current is! Map) throw const SiftHttpException('No forecast available.');

    final currentTemp = (current['temperature_2m'] as num?)?.toDouble();
    final feelsLike = (current['apparent_temperature'] as num?)?.toDouble();
    final humidity = (current['relative_humidity_2m'] as num?)?.toInt();
    final wind = (current['wind_speed_10m'] as num?)?.toDouble();
    final codeIndex = tomorrow ? 1 : 0;
    int? dailyCode;
    double? high;
    double? low;
    String? sunrise;
    String? sunset;
    if (daily is Map) {
      final codes = daily['weather_code'];
      final highs = daily['temperature_2m_max'];
      final lows = daily['temperature_2m_min'];
      final sunrises = daily['sunrise'];
      final sunsets = daily['sunset'];
      if (codes is List && codes.length > codeIndex) {
        dailyCode = (codes[codeIndex] as num?)?.toInt();
      }
      if (highs is List && highs.length > codeIndex) {
        high = (highs[codeIndex] as num?)?.toDouble();
      }
      if (lows is List && lows.length > codeIndex) {
        low = (lows[codeIndex] as num?)?.toDouble();
      }
      if (sunrises is List && sunrises.length > codeIndex) {
        sunrise = _clock(sunrises[codeIndex]?.toString());
      }
      if (sunsets is List && sunsets.length > codeIndex) {
        sunset = _clock(sunsets[codeIndex]?.toString());
      }
    }

    final currentCode = (current['weather_code'] as num?)?.toInt();
    final condition = _condition(dailyCode ?? currentCode);
    final placeLine = [
      name,
      if (region.isNotEmpty && region != name) region,
      if (country.isNotEmpty) country,
    ].join(', ');
    final tempValue = (tomorrow ? high : currentTemp) ?? currentTemp;
    final facts = <AnswerFact>[
      if (tempValue != null)
        AnswerFact(
          tomorrow ? 'High' : 'Now',
          '${_formatTemperature(tempValue)} · ${_formatFahrenheit(tempValue)}',
        ),
      if (!tomorrow && feelsLike != null)
        AnswerFact('Feels like', '${_formatTemperature(feelsLike)} · '
            '${_formatFahrenheit(feelsLike)}'),
      if (high != null && low != null)
        AnswerFact(
          'Daily range',
          '${_formatTemperature(low)} to ${_formatTemperature(high)}',
        ),
      if (wind != null) AnswerFact('Wind', '${_formatNumber(wind)} km/h'),
      if (humidity != null) AnswerFact('Humidity', '$humidity%'),
      if (sunrise != null) AnswerFact('Sunrise', sunrise),
      if (sunset != null) AnswerFact('Sunset', sunset),
    ];

    return InstantAnswer(
      kind: 'weather',
      title: placeLine,
      subtitle: '${condition ?? 'Current conditions'}'
          '${countryCode.isEmpty ? '' : ' · $countryCode'}',
      body: tomorrow
          ? 'Tomorrow’s outlook for this place.'
          : 'Live conditions from the nearest Open-Meteo grid point.',
      facts: facts,
      link: 'https://open-meteo.com/',
      linkLabel: 'Open-Meteo forecast',
      source: 'Open-Meteo · live weather',
      isLive: true,
    );
  }

  String _formatTemperature(double value) => '${_formatNumber(value)}°C';

  String _formatFahrenheit(double celsius) =>
      '${_formatNumber(celsius * 9 / 5 + 32)}°F';

  String? _clock(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final time = DateTime.tryParse(iso);
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  String? _condition(int? code) {
    if (code == null) return null;
    return switch (code) {
      0 => 'Clear sky',
      1 => 'Mainly clear',
      2 => 'Partly cloudy',
      3 => 'Overcast',
      45 || 48 => 'Fog',
      51 || 53 || 55 => 'Drizzle',
      56 || 57 => 'Freezing drizzle',
      61 || 63 || 65 => 'Rain',
      66 || 67 => 'Freezing rain',
      71 || 73 || 75 => 'Snow',
      77 => 'Snow grains',
      80 || 81 || 82 => 'Rain showers',
      85 || 86 => 'Snow showers',
      95 => 'Thunderstorm',
      96 || 99 => 'Thunderstorm with hail',
      _ => 'Current conditions',
    };
  }

  /* ------------------------------------------------------------------------
   * Dictionary
   * ---------------------------------------------------------------------- */

  String? _dictionaryWord(String raw) {
    final query = raw.trim().replaceAll(RegExp(r'[?!.]+$'), '');
    final patterns = [
      RegExp(r'^define\s+(.+)$', caseSensitive: false),
      RegExp(r'^definition of\s+(.+)$', caseSensitive: false),
      RegExp(r'^meaning of\s+(.+)$', caseSensitive: false),
      RegExp(r'^what does\s+(.+?)\s+mean$', caseSensitive: false),
      RegExp(r'^(.+?)\s+meaning$', caseSensitive: false),
      RegExp(r'^(.+?)\s+definition$', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(query);
      if (match == null) continue;
      final word = match.group(1)!.trim().toLowerCase();
      if (RegExp(r"^[a-z][a-z' -]{0,48}$").hasMatch(word) &&
          !word.contains('  ')) {
        return word;
      }
    }
    return null;
  }

  Future<InstantAnswer> _dictionary(String word) async {
    final uri = Uri.https(
      'api.dictionaryapi.dev',
      '/api/v2/entries/en/${Uri.encodeComponent(word)}',
    );
    final body = await _http.getString(
      uri.toString(),
      timeout: const Duration(seconds: 7),
      cacheSeconds: 86400,
    );
    final decoded = jsonDecode(body);
    if (decoded is! List || decoded.isEmpty) {
      throw const SiftHttpException('Word not found.');
    }
    final entry = decoded.first;
    if (entry is! Map) throw const SiftHttpException('Word not found.');
    final displayWord = entry['word']?.toString() ?? word;
    var phonetic = entry['phonetic']?.toString() ?? '';
    final phonetics = entry['phonetics'];
    if (phonetic.isEmpty && phonetics is List) {
      for (final item in phonetics.whereType<Map>()) {
        final text = item['text']?.toString();
        if (text != null && text.isNotEmpty) {
          phonetic = text;
          break;
        }
      }
    }

    final facts = <AnswerFact>[];
    String? firstDefinition;
    String? firstPart;
    final meanings = entry['meanings'];
    if (meanings is List) {
      for (final meaning in meanings.whereType<Map>().take(3)) {
        final part = meaning['partOfSpeech']?.toString() ?? '';
        final definitions = meaning['definitions'];
        if (definitions is! List) continue;
        for (final definition in definitions.whereType<Map>().take(2)) {
          final text = stripHtml(definition['definition']?.toString() ?? '');
          if (text.isEmpty) continue;
          firstDefinition ??= text;
          firstPart ??= part;
          facts.add(
            AnswerFact(
              part.isEmpty ? 'Definition' : part,
              truncateText(text, 220),
            ),
          );
        }
      }
    }
    if (firstDefinition == null) {
      throw const SiftHttpException('No definition available.');
    }
    final sourceUrl = 'https://en.wiktionary.org/wiki/${Uri.encodeComponent(displayWord)}';
    return InstantAnswer(
      kind: 'dictionary',
      title: displayWord,
      subtitle: [
        if (phonetic.isNotEmpty) phonetic,
        if (firstPart != null && firstPart.isNotEmpty) firstPart,
      ].join(' · '),
      body: firstDefinition,
      facts: facts.take(4).toList(),
      link: sourceUrl,
      linkLabel: 'Open on Wiktionary',
      source: 'dictionaryapi.dev · Wiktionary data',
    );
  }

  /* ------------------------------------------------------------------------
   * Number formatting
   * ---------------------------------------------------------------------- */

  String _formatNumber(double value) {
    if (!value.isFinite) return '—';
    final abs = value.abs();
    if (abs != 0 && (abs >= 1e12 || abs < 1e-6)) {
      return value.toStringAsExponential(4).replaceAll('.0000e', 'e');
    }
    final rounded = double.parse(value.toStringAsFixed(6));
    if (rounded == rounded.roundToDouble()) {
      return rounded.round().toString();
    }
    var text = rounded.toStringAsFixed(6);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text;
  }
}

class _Conversion {
  const _Conversion({
    required this.amount,
    required this.from,
    required this.to,
    this.isCurrency = false,
  });

  final double amount;
  final String from;
  final String to;
  final bool isCurrency;
}

class _Unit {
  const _Unit({
    required this.key,
    required this.dimension,
    required this.factor,
    required this.label,
    required this.singular,
    this.celsiusOffset,
  });

  final String key;
  final String dimension;
  final double factor;
  final String label;
  final String singular;
  final double? celsiusOffset;

  double toCelsius(double value) {
    if (key == 'celsius') return value;
    if (key == 'fahrenheit') return (value - 32) * 5 / 9;
    if (key == 'kelvin') return value - 273.15;
    return value;
  }

  double fromCelsius(double value) {
    if (key == 'celsius') return value;
    if (key == 'fahrenheit') return value * 9 / 5 + 32;
    if (key == 'kelvin') return value + 273.15;
    return value;
  }
}

const Map<String, _Unit> _units = {
  // Length (base: metre)
  'mm': _Unit(key: 'mm', dimension: 'length', factor: 0.001, label: 'millimetres', singular: 'millimetre'),
  'centimeter': _Unit(key: 'centimeter', dimension: 'length', factor: 0.01, label: 'centimetres', singular: 'centimetre'),
  'm': _Unit(key: 'm', dimension: 'length', factor: 1, label: 'metres', singular: 'metre'),
  'km': _Unit(key: 'km', dimension: 'length', factor: 1000, label: 'kilometres', singular: 'kilometre'),
  'inch': _Unit(key: 'inch', dimension: 'length', factor: 0.0254, label: 'inches', singular: 'inch'),
  'foot': _Unit(key: 'foot', dimension: 'length', factor: 0.3048, label: 'feet', singular: 'foot'),
  'yard': _Unit(key: 'yard', dimension: 'length', factor: 0.9144, label: 'yards', singular: 'yard'),
  'mile': _Unit(key: 'mile', dimension: 'length', factor: 1609.344, label: 'miles', singular: 'mile'),
  'nauticalmile': _Unit(key: 'nauticalmile', dimension: 'length', factor: 1852, label: 'nautical miles', singular: 'nautical mile'),
  // Mass (base: kilogram)
  'mg': _Unit(key: 'mg', dimension: 'mass', factor: 1e-6, label: 'milligrams', singular: 'milligram'),
  'g': _Unit(key: 'g', dimension: 'mass', factor: 0.001, label: 'grams', singular: 'gram'),
  'kg': _Unit(key: 'kg', dimension: 'mass', factor: 1, label: 'kilograms', singular: 'kilogram'),
  'tonne': _Unit(key: 'tonne', dimension: 'mass', factor: 1000, label: 'tonnes', singular: 'tonne'),
  'ounce': _Unit(key: 'ounce', dimension: 'mass', factor: 0.028349523125, label: 'ounces', singular: 'ounce'),
  'pound': _Unit(key: 'pound', dimension: 'mass', factor: 0.45359237, label: 'pounds', singular: 'pound'),
  'stone': _Unit(key: 'stone', dimension: 'mass', factor: 6.35029318, label: 'stone', singular: 'stone'),
  // Volume (base: litre)
  'ml': _Unit(key: 'ml', dimension: 'volume', factor: 0.001, label: 'millilitres', singular: 'millilitre'),
  'litre': _Unit(key: 'litre', dimension: 'volume', factor: 1, label: 'litres', singular: 'litre'),
  'teaspoon': _Unit(key: 'teaspoon', dimension: 'volume', factor: 0.00492892, label: 'teaspoons', singular: 'teaspoon'),
  'tablespoon': _Unit(key: 'tablespoon', dimension: 'volume', factor: 0.0147868, label: 'tablespoons', singular: 'tablespoon'),
  'cup': _Unit(key: 'cup', dimension: 'volume', factor: 0.236588, label: 'cups', singular: 'cup'),
  'pint': _Unit(key: 'pint', dimension: 'volume', factor: 0.473176, label: 'pints', singular: 'pint'),
  'quart': _Unit(key: 'quart', dimension: 'volume', factor: 0.946353, label: 'quarts', singular: 'quart'),
  'gallon': _Unit(key: 'gallon', dimension: 'volume', factor: 3.78541, label: 'US gallons', singular: 'US gallon'),
  'fluidounce': _Unit(key: 'fluidounce', dimension: 'volume', factor: 0.0295735, label: 'US fluid ounces', singular: 'US fluid ounce'),
  // Area (base: square metre)
  'm2': _Unit(key: 'm2', dimension: 'area', factor: 1, label: 'square metres', singular: 'square metre'),
  'km2': _Unit(key: 'km2', dimension: 'area', factor: 1e6, label: 'square kilometres', singular: 'square kilometre'),
  'ft2': _Unit(key: 'ft2', dimension: 'area', factor: 0.092903, label: 'square feet', singular: 'square foot'),
  'mi2': _Unit(key: 'mi2', dimension: 'area', factor: 2589988.11, label: 'square miles', singular: 'square mile'),
  'acre': _Unit(key: 'acre', dimension: 'area', factor: 4046.8564224, label: 'acres', singular: 'acre'),
  'hectare': _Unit(key: 'hectare', dimension: 'area', factor: 10000, label: 'hectares', singular: 'hectare'),
  // Speed (base: metre per second)
  'mps': _Unit(key: 'mps', dimension: 'speed', factor: 1, label: 'metres per second', singular: 'metre per second'),
  'kph': _Unit(key: 'kph', dimension: 'speed', factor: 1 / 3.6, label: 'kilometres per hour', singular: 'kilometre per hour'),
  'mph': _Unit(key: 'mph', dimension: 'speed', factor: 0.44704, label: 'miles per hour', singular: 'mile per hour'),
  'knot': _Unit(key: 'knot', dimension: 'speed', factor: 0.514444, label: 'knots', singular: 'knot'),
  // Data (base: byte)
  'byte': _Unit(key: 'byte', dimension: 'data', factor: 1, label: 'bytes', singular: 'byte'),
  'kilobyte': _Unit(key: 'kilobyte', dimension: 'data', factor: 1000, label: 'kilobytes', singular: 'kilobyte'),
  'megabyte': _Unit(key: 'megabyte', dimension: 'data', factor: 1e6, label: 'megabytes', singular: 'megabyte'),
  'gigabyte': _Unit(key: 'gigabyte', dimension: 'data', factor: 1e9, label: 'gigabytes', singular: 'gigabyte'),
  'terabyte': _Unit(key: 'terabyte', dimension: 'data', factor: 1e12, label: 'terabytes', singular: 'terabyte'),
  // Time (base: second)
  'second': _Unit(key: 'second', dimension: 'time', factor: 1, label: 'seconds', singular: 'second'),
  'minute': _Unit(key: 'minute', dimension: 'time', factor: 60, label: 'minutes', singular: 'minute'),
  'hour': _Unit(key: 'hour', dimension: 'time', factor: 3600, label: 'hours', singular: 'hour'),
  'day': _Unit(key: 'day', dimension: 'time', factor: 86400, label: 'days', singular: 'day'),
  'week': _Unit(key: 'week', dimension: 'time', factor: 604800, label: 'weeks', singular: 'week'),
  'year': _Unit(key: 'year', dimension: 'time', factor: 31557600, label: 'years', singular: 'year'),
  // Energy (base: joule)
  'joule': _Unit(key: 'joule', dimension: 'energy', factor: 1, label: 'joules', singular: 'joule'),
  'kilojoule': _Unit(key: 'kilojoule', dimension: 'energy', factor: 1000, label: 'kilojoules', singular: 'kilojoule'),
  'calorie': _Unit(key: 'calorie', dimension: 'energy', factor: 4.184, label: 'calories', singular: 'calorie'),
  'kilocalorie': _Unit(key: 'kilocalorie', dimension: 'energy', factor: 4184, label: 'kilocalories', singular: 'kilocalorie'),
  'watt hour': _Unit(key: 'watt hour', dimension: 'energy', factor: 3600, label: 'watt hours', singular: 'watt hour'),
  'kilowatt hour': _Unit(key: 'kilowatt hour', dimension: 'energy', factor: 3.6e6, label: 'kilowatt hours', singular: 'kilowatt hour'),
  // Pressure (base: pascal)
  'pascal': _Unit(key: 'pascal', dimension: 'pressure', factor: 1, label: 'pascals', singular: 'pascal'),
  'kilopascal': _Unit(key: 'kilopascal', dimension: 'pressure', factor: 1000, label: 'kilopascals', singular: 'kilopascal'),
  'bar': _Unit(key: 'bar', dimension: 'pressure', factor: 100000, label: 'bar', singular: 'bar'),
  'psi': _Unit(key: 'psi', dimension: 'pressure', factor: 6894.757, label: 'psi', singular: 'psi'),
  'atmosphere': _Unit(key: 'atmosphere', dimension: 'pressure', factor: 101325, label: 'atmospheres', singular: 'atmosphere'),
  // Temperature
  'celsius': _Unit(key: 'celsius', dimension: 'temperature', factor: 1, label: '°C', singular: 'degree Celsius'),
  'fahrenheit': _Unit(key: 'fahrenheit', dimension: 'temperature', factor: 1, label: '°F', singular: 'degree Fahrenheit'),
  'kelvin': _Unit(key: 'kelvin', dimension: 'temperature', factor: 1, label: 'K', singular: 'kelvin'),
  // Power (base: watt)
  'watt': _Unit(key: 'watt', dimension: 'power', factor: 1, label: 'watts', singular: 'watt'),
  'kilowatt': _Unit(key: 'kilowatt', dimension: 'power', factor: 1000, label: 'kilowatts', singular: 'kilowatt'),
  'horsepower': _Unit(key: 'horsepower', dimension: 'power', factor: 745.699872, label: 'horsepower', singular: 'horsepower'),
  // Angle (base: degree)
  'degree': _Unit(key: 'degree', dimension: 'angle', factor: 1, label: 'degrees', singular: 'degree'),
  'radian': _Unit(key: 'radian', dimension: 'angle', factor: 180 / math.pi, label: 'radians', singular: 'radian'),
};

const Map<String, String> _unitAliases = {
  'millimeter': 'mm', 'millimeters': 'mm', 'millimetre': 'mm', 'millimetres': 'mm',
  'centimeter': 'centimeter', 'centimeters': 'centimeter', 'centimetre': 'centimeter', 'centimetres': 'centimeter', 'cm': 'centimeter',
  'meter': 'm', 'meters': 'm', 'metre': 'm', 'metres': 'm',
  'kilometer': 'km', 'kilometers': 'km', 'kilometre': 'km', 'kilometres': 'km',
  'inch': 'inch', 'inches': 'inch', 'in': 'inch',
  'foot': 'foot', 'feet': 'foot', 'ft': 'foot',
  'yard': 'yard', 'yards': 'yard', 'yd': 'yard',
  'mile': 'mile', 'miles': 'mile', 'mi': 'mile',
  'nautical mile': 'nauticalmile', 'nautical miles': 'nauticalmile', 'nmi': 'nauticalmile', 'nm': 'nauticalmile',
  'milligram': 'mg', 'milligrams': 'mg',
  'gram': 'g', 'grams': 'g',
  'kilogram': 'kg', 'kilograms': 'kg', 'kilo': 'kg', 'kilos': 'kg',
  'tonne': 'tonne', 'tonnes': 'tonne', 'ton': 'tonne', 'tons': 'tonne', 't': 'tonne',
  'ounce': 'ounce', 'ounces': 'ounce', 'oz': 'ounce',
  'pound': 'pound', 'pounds': 'pound', 'lb': 'pound', 'lbs': 'pound',
  'stone': 'stone', 'st': 'stone',
  'milliliter': 'ml', 'milliliters': 'ml', 'millilitre': 'ml', 'millilitres': 'ml',
  'liter': 'litre', 'liters': 'litre', 'litre': 'litre', 'litres': 'litre', 'l': 'litre',
  'teaspoon': 'teaspoon', 'teaspoons': 'teaspoon', 'tsp': 'teaspoon',
  'tablespoon': 'tablespoon', 'tablespoons': 'tablespoon', 'tbsp': 'tablespoon',
  'cup': 'cup', 'cups': 'cup',
  'pint': 'pint', 'pints': 'pint', 'pt': 'pint',
  'quart': 'quart', 'quarts': 'quart', 'qt': 'quart',
  'gallon': 'gallon', 'gallons': 'gallon', 'gal': 'gallon',
  'fluid ounce': 'fluidounce', 'fluid ounces': 'fluidounce', 'fl oz': 'fluidounce', 'floz': 'fluidounce',
  'sq m': 'm2', 'square meter': 'm2', 'square meters': 'm2', 'square metre': 'm2', 'square metres': 'm2',
  'sq km': 'km2', 'square kilometer': 'km2', 'square kilometers': 'km2', 'square kilometre': 'km2', 'square kilometres': 'km2',
  'sq ft': 'ft2', 'square foot': 'ft2', 'square feet': 'ft2',
  'sq mi': 'mi2', 'square mile': 'mi2', 'square miles': 'mi2',
  'acre': 'acre', 'acres': 'acre',
  'hectare': 'hectare', 'hectares': 'hectare', 'ha': 'hectare',
  'm/s': 'mps', 'mps': 'mps', 'meters per second': 'mps', 'metres per second': 'mps',
  'km/h': 'kph', 'kph': 'kph', 'kmh': 'kph', 'kilometers per hour': 'kph', 'kilometres per hour': 'kph',
  'mi/h': 'mph', 'mph': 'mph', 'miles per hour': 'mph',
  'knot': 'knot', 'knots': 'knot', 'kt': 'knot',
  'byte': 'byte', 'bytes': 'byte', 'b': 'byte',
  'kilobyte': 'kilobyte', 'kilobytes': 'kilobyte', 'kb': 'kilobyte',
  'megabyte': 'megabyte', 'megabytes': 'megabyte', 'mb': 'megabyte',
  'gigabyte': 'gigabyte', 'gigabytes': 'gigabyte', 'gb': 'gigabyte',
  'terabyte': 'terabyte', 'terabytes': 'terabyte', 'tb': 'terabyte',
  'second': 'second', 'seconds': 'second', 'sec': 'second', 'secs': 'second', 's': 'second',
  'minute': 'minute', 'minutes': 'minute', 'min': 'minute', 'mins': 'minute',
  'hour': 'hour', 'hours': 'hour', 'hr': 'hour', 'hrs': 'hour', 'h': 'hour',
  'day': 'day', 'days': 'day',
  'week': 'week', 'weeks': 'week',
  'year': 'year', 'years': 'year', 'yr': 'year', 'yrs': 'year',
  'joule': 'joule', 'joules': 'joule', 'j': 'joule',
  'kilojoule': 'kilojoule', 'kilojoules': 'kilojoule', 'kj': 'kilojoule',
  'calorie': 'calorie', 'calories': 'calorie', 'cal': 'calorie',
  'kilocalorie': 'kilocalorie', 'kilocalories': 'kilocalorie', 'kcal': 'kilocalorie',
  'watt hour': 'watt hour', 'watt hours': 'watt hour', 'wh': 'watt hour',
  'kilowatt hour': 'kilowatt hour', 'kilowatt hours': 'kilowatt hour', 'kwh': 'kilowatt hour',
  'pascal': 'pascal', 'pascals': 'pascal', 'pa': 'pascal',
  'kilopascal': 'kilopascal', 'kilopascals': 'kilopascal', 'kpa': 'kilopascal',
  'bar': 'bar', 'bars': 'bar',
  'psi': 'psi',
  'atmosphere': 'atmosphere', 'atmospheres': 'atmosphere', 'atm': 'atmosphere',
  'celsius': 'celsius', '°c': 'celsius', 'centigrade': 'celsius',
  'fahrenheit': 'fahrenheit', '°f': 'fahrenheit',
  'kelvin': 'kelvin', 'k': 'kelvin',
  'watt': 'watt', 'watts': 'watt', 'w': 'watt',
  'kilowatt': 'kilowatt', 'kilowatts': 'kilowatt', 'kw': 'kilowatt',
  'horsepower': 'horsepower', 'hp': 'horsepower',
  'degree': 'degree', 'degrees': 'degree', 'deg': 'degree', '°': 'degree',
  'radian': 'radian', 'radians': 'radian', 'rad': 'radian',
};

_Unit? _unitFor(String raw) {
  var value = raw.trim().toLowerCase();
  value = value.replaceAll(RegExp(r'[.]'), '');
  value = value.replaceAll(RegExp(r'\s+'), ' ');
  final key = _unitAliases[value] ?? (value == 'm' ? 'm' : null);
  if (key == null) return null;
  return _units[key];
}

const Map<String, String> _currencies = {
  'usd': 'US dollar', 'eur': 'Euro', 'gbp': 'British pound', 'jpy': 'Japanese yen',
  'aud': 'Australian dollar', 'cad': 'Canadian dollar', 'chf': 'Swiss franc',
  'cny': 'Chinese yuan', 'hkd': 'Hong Kong dollar', 'nzd': 'New Zealand dollar',
  'sek': 'Swedish krona', 'nok': 'Norwegian krone', 'dkk': 'Danish krone',
  'pln': 'Polish złoty', 'czk': 'Czech koruna', 'huf': 'Hungarian forint',
  'ron': 'Romanian leu', 'bgn': 'Bulgarian lev', 'hrk': 'Croatian kuna',
  'isk': 'Icelandic króna', 'try': 'Turkish lira', 'zar': 'South African rand',
  'brl': 'Brazilian real', 'inr': 'Indian rupee', 'mxn': 'Mexican peso',
  'krw': 'South Korean won', 'sgd': 'Singapore dollar', 'thb': 'Thai baht',
  'myr': 'Malaysian ringgit', 'php': 'Philippine peso', 'idr': 'Indonesian rupiah',
  'ils': 'Israeli new shekel',
};

/* --------------------------------------------------------------------------
 * Recursive-descent expression parser
 * ------------------------------------------------------------------------ */

class _MathParser {
  _MathParser(String input) : _tokens = _tokenize(input);

  final List<_MathToken> _tokens;
  int _index = 0;

  static List<_MathToken> _tokenize(String input) {
    final tokens = <_MathToken>[];
    var i = 0;
    while (i < input.length) {
      final char = input[i];
      if (char.trim().isEmpty) {
        i += 1;
        continue;
      }
      if (RegExp(r'[0-9.]').hasMatch(char)) {
        final start = i;
        var dots = 0;
        while (i < input.length &&
            (RegExp(r'[0-9]').hasMatch(input[i]) ||
                (input[i] == '.' && dots == 0))) {
          if (input[i] == '.') dots += 1;
          i += 1;
        }
        final text = input.substring(start, i);
        final value = double.tryParse(text);
        if (value == null) throw FormatException('Bad number: $text');
        tokens.add(_MathToken.number(value));
        continue;
      }
      if (RegExp(r'[a-z]').hasMatch(char)) {
        final start = i;
        while (i < input.length && RegExp(r'[a-z]').hasMatch(input[i])) {
          i += 1;
        }
        tokens.add(_MathToken.ident(input.substring(start, i)));
        continue;
      }
      if ('+-*/^%()'.contains(char)) {
        tokens.add(_MathToken.operator(char));
        i += 1;
        continue;
      }
      throw FormatException('Unexpected character: $char');
    }
    return tokens;
  }

  double parse() {
    final value = _expression();
    if (_index != _tokens.length) {
      throw const FormatException('Unexpected trailing input.');
    }
    return value;
  }

  double _expression() {
    var value = _term();
    while (_match('+') || _match('-')) {
      final operator = _tokens[_index - 1].text;
      final right = _term();
      value = operator == '+' ? value + right : value - right;
    }
    return value;
  }

  double _term() {
    var value = _unary();
    while (true) {
      if (_match('*')) {
        value *= _unary();
      } else if (_match('/')) {
        final divisor = _unary();
        if (divisor == 0) throw UnsupportedError('Division by zero');
        value /= divisor;
      } else if (_startsValue()) {
        value *= _unary();
      } else {
        break;
      }
    }
    return value;
  }

  double _unary() {
    if (_match('+')) return _unary();
    if (_match('-')) return -_unary();
    return _power();
  }

  double _power() {
    final base = _primaryWithPercent();
    if (_match('^')) return math.pow(base, _unary()).toDouble();
    return base;
  }

  double _primaryWithPercent() {
    var value = _primary();
    while (_match('%')) {
      value /= 100;
    }
    return value;
  }

  double _primary() {
    if (_match('(')) {
      final value = _expression();
      _expect(')');
      return value;
    }
    final token = _peek();
    if (token == null) throw const FormatException('Missing value.');
    if (token.isNumber) {
      _index += 1;
      return token.numberValue!;
    }
    if (token.isIdent) {
      _index += 1;
      final name = token.text;
      if (name == 'pi') return math.pi;
      if (name == 'e') return math.e;
      if (!_match('(')) {
        throw FormatException('Unknown name: $name');
      }
      final argument = _expression();
      _expect(')');
      return switch (name) {
        'sqrt' => math.sqrt(argument),
        'sin' => math.sin(argument),
        'cos' => math.cos(argument),
        'tan' => math.tan(argument),
        'log' => math.log(argument) / math.ln10,
        'ln' => math.log(argument),
        'abs' => argument.abs(),
        'round' => argument.roundToDouble(),
        'floor' => argument.floorToDouble(),
        'ceil' => argument.ceilToDouble(),
        _ => throw FormatException('Unknown function: $name'),
      };
    }
    throw const FormatException('Unexpected token.');
  }

  bool _startsValue() {
    final token = _peek();
    if (token == null) return false;
    return token.isNumber || token.isIdent || token.text == '(';
  }

  _MathToken? _peek() => _index >= _tokens.length ? null : _tokens[_index];

  bool _match(String text) {
    final token = _peek();
    if (token == null || token.text != text) return false;
    _index += 1;
    return true;
  }

  void _expect(String text) {
    if (!_match(text)) throw FormatException('Expected $text.');
  }
}

class _MathToken {
  const _MathToken._(this.text, this.numberValue, {this.isIdent = false});

  factory _MathToken.number(double value) => _MathToken._('$value', value);

  factory _MathToken.ident(String name) =>
      _MathToken._(name, null, isIdent: true);

  factory _MathToken.operator(String text) => _MathToken._(text, null);

  final String text;
  final double? numberValue;
  final bool isIdent;

  bool get isNumber => numberValue != null;
}
