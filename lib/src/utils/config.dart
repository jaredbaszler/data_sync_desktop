import 'dart:io';

class Config {
  final String googlePlacesApiKey;
  final String mongodbUri;
  final String mongodbDatabase;
  final String mongodbCollection;
  final double searchRadiusMiles;
  final List<String> debugAirports;

  Config({
    required this.googlePlacesApiKey,
    required this.mongodbUri,
    required this.mongodbDatabase,
    required this.mongodbCollection,
    this.searchRadiusMiles = 10.0,
    this.debugAirports = const [],
  });

  factory Config.fromEnvironment() {
    // Load env.production file if it exists
    _loadEnvFile('env.production');

    // Load .env.local overrides (takes precedence over .env)
    _loadEnvFile('.env.local', override: true);

    final debugAirportsRaw = _getEnv('DEBUG_AIRPORTS', defaultValue: '');
    final debugAirports = debugAirportsRaw.isEmpty
        ? <String>[]
        : debugAirportsRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    return Config(
      googlePlacesApiKey: _getEnv('GOOGLE_API_KEY'),
      mongodbUri: _getEnv('DB_URL'),
      mongodbDatabase: _getEnv('DB_NAME', defaultValue: 'avtopia_devdb'),
      mongodbCollection: _getEnv('MONGODB_COLLECTION', defaultValue: 'avtopia_business'),
      searchRadiusMiles: double.tryParse(
            _getEnv('SEARCH_RADIUS_MILES', defaultValue: '10'),
          ) ??
          10.0,
      debugAirports: debugAirports,
    );
  }

  static final Map<String, String> _envOverrides = {};

  static void _loadEnvFile(String path, {bool override = false}) {
    final file = File(path);
    if (!file.existsSync()) return;
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex == -1) continue;
      final key = trimmed.substring(0, eqIndex).trim();
      var value = trimmed.substring(eqIndex + 1).trim();
      // Strip surrounding quotes if present
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
           (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (override || Platform.environment[key] == null) {
        _envOverrides[key] = value;
      }
    }
  }

  static String _getEnv(String key, {String? defaultValue}) {
    final value = Platform.environment[key] ?? _envOverrides[key] ?? defaultValue;
    if (value == null) {
      throw StateError('Missing required environment variable: $key');
    }
    return value;
  }
}
