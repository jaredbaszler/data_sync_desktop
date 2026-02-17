import 'dart:convert';
import 'dart:io';

/// Manages checkpoint/resume state and error logging for interrupted runs.
class CacheRepository {
  static const _checkpointFile = 'checkpoint.json';
  static const _errorLogFile = 'error_log.json';

  Map<String, dynamic> _checkpoint = {};
  final List<Map<String, dynamic>> _errors = [];

  /// Load checkpoint from disk
  Future<void> loadCheckpoint() async {
    final file = File(_checkpointFile);
    if (await file.exists()) {
      try {
        _checkpoint = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        print('Loaded checkpoint: last airport=${_checkpoint['lastAirportCode']}, '
            'processed=${_checkpoint['airportsProcessed']}');
      } catch (e) {
        print('Error loading checkpoint: $e - starting fresh');
        _checkpoint = {};
      }
    }
  }

  /// Save checkpoint to disk
  Future<void> saveCheckpoint({
    required String lastAirportCode,
    required int airportsProcessed,
    required int businessesFound,
    required int businessesSkipped,
  }) async {
    _checkpoint = {
      'lastAirportCode': lastAirportCode,
      'airportsProcessed': airportsProcessed,
      'businessesFound': businessesFound,
      'businessesSkipped': businessesSkipped,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await File(_checkpointFile).writeAsString(jsonEncode(_checkpoint));
  }

  /// Get the last processed airport code (for resume)
  String? get lastAirportCode => _checkpoint['lastAirportCode'] as String?;

  /// Get the number of airports processed so far
  int get airportsProcessed => _checkpoint['airportsProcessed'] as int? ?? 0;

  /// Log an error for later review
  void logError({
    required String airportCode,
    required String? placeId,
    required String error,
    String? businessName,
  }) {
    _errors.add({
      'airportCode': airportCode,
      'placeId': placeId,
      'businessName': businessName,
      'error': error,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Save error log to disk
  Future<void> saveErrorLog() async {
    if (_errors.isEmpty) return;
    await File(_errorLogFile).writeAsString(
      const JsonEncoder.withIndent('  ').convert(_errors),
    );
    print('Saved ${_errors.length} errors to $_errorLogFile');
  }

  /// Clear checkpoint file (on successful completion)
  Future<void> clearCheckpoint() async {
    final file = File(_checkpointFile);
    if (await file.exists()) {
      await file.delete();
    }
    _checkpoint = {};
  }

  int get errorCount => _errors.length;
}
