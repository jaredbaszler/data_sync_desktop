import 'package:mongo_dart/mongo_dart.dart';

import '../utils/config.dart';

class MongoDbClient {
  final Config config;
  late Db _db;
  bool _connected = false;

  MongoDbClient(this.config);

  Db get db => _db;
  bool get isConnected => _connected;

  Future<void> connect() async {
    if (_connected) return;

    _db = await Db.create(config.mongodbUri);
    await _db.open();

    // Select the database
    if (_db.databaseName != config.mongodbDatabase) {
      _db = await Db.create('${config.mongodbUri}${config.mongodbDatabase}');
      await _db.open();
    }

    _connected = true;
    print('Connected to MongoDB: ${config.mongodbDatabase}');
  }

  Future<void> reconnect() async {
    _connected = false;
    try {
      await _db.close();
    } catch (_) {}
    _db = await Db.create(config.mongodbUri);
    await _db.open();
    if (_db.databaseName != config.mongodbDatabase) {
      _db = await Db.create('${config.mongodbUri}${config.mongodbDatabase}');
      await _db.open();
    }
    _connected = true;
    print('Reconnected to MongoDB');
  }

  DbCollection collection(String name) {
    if (!_connected) {
      throw StateError('Not connected to MongoDB. Call connect() first.');
    }
    return _db.collection(name);
  }

  Future<void> close() async {
    if (_connected) {
      await _db.close();
      _connected = false;
      print('Disconnected from MongoDB');
    }
  }
}
