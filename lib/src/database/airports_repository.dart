import 'package:mongo_dart/mongo_dart.dart';

import '../models/airport.dart';
import 'mongodb_client.dart';

class AirportsRepository {
  static const collectionName = 'airports';

  final MongoDbClient _client;

  AirportsRepository(this._client);

  DbCollection get _collection => _client.collection(collectionName);

  Future<void> ensureIndexes() async {
    await _collection.createIndex(keys: {'state': 1});
    await _collection.createIndex(keys: {'enabled': 1});
  }

  Future<List<Airport>> getEnabledAirports({int? limit}) async {
    final query = where.eq('enabled', true).sortBy('_id');
    if (limit != null) {
      query.limit(limit);
    }
    final docs = await _collection.find(query).toList();
    return docs.map((d) => Airport.fromMongoDocument(d)).toList();
  }

  Future<Airport?> getByIcaoCode(String icaoCode) async {
    final doc = await _collection.findOne(where.eq('_id',icaoCode));
    return doc != null ? Airport.fromMongoDocument(doc) : null;
  }

  Future<void> upsertAirport(Airport airport) async {
    await _collection.replaceOne(
      where.eq('_id',airport.icaoCode),
      airport.toMongoDocument(),
      upsert: true,
    );
  }

  Future<void> upsertMany(List<Airport> airports) async {
    for (final airport in airports) {
      await upsertAirport(airport);
    }
  }

  Future<void> markProcessed(String icaoCode) async {
    await _collection.updateOne(
      where.eq('_id',icaoCode),
      modify.set('lastProcessed', DateTime.now()).set('updatedAt', DateTime.now()),
    );
  }

  Future<int> count() async {
    return await _collection.count();
  }

  Future<List<Airport>> getUnprocessedAirports({int? limit}) async {
    final query = where.eq('enabled', true).eq('lastProcessed', null).sortBy('_id');
    if (limit != null) {
      query.limit(limit);
    }
    final docs = await _collection.find(query).toList();
    return docs.map((d) => Airport.fromMongoDocument(d)).toList();
  }
}
