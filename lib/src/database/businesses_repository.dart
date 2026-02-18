import 'package:mongo_dart/mongo_dart.dart';

import '../models/business.dart';
import 'mongodb_client.dart';

class BusinessesRepository {
  final MongoDbClient _client;
  final String collectionName;

  BusinessesRepository(this._client, {this.collectionName = 'avtopia_business'});

  DbCollection get _collection => _client.collection(collectionName);

  Future<void> ensureIndexes() async {
    try {
      await _collection.createIndex(keys: {'placeId': 1}, unique: true, sparse: true);
    } catch (e) {
      // Extract duplicate placeId from error if present
      final errStr = e.toString();
      final dupMatch = RegExp(r'dup key: \{ placeId: "(.+?)" \}').firstMatch(errStr);
      if (dupMatch != null) {
        print('WARNING: Duplicate placeId found: "${dupMatch.group(1)}"');
        print('  Cannot create unique index until duplicates are resolved.');
      } else {
        print('WARNING: Could not create unique placeId index: $e');
      }
    }
    await _collection.createIndex(keys: {'airportCode': 1});
    await _collection.createIndex(keys: {'updatedAt': 1});
  }

  Future<Business?> findByPlaceId(String placeId) async {
    final doc = await _collection.findOne(where.eq('placeId', placeId));
    return doc != null ? Business.fromMongoDocument(doc) : null;
  }

  Future<List<Business>> findByAirportCode(String airportCode) async {
    final docs = await _collection.find(where.eq('airportCode', airportCode)).toList();
    return docs.map((d) => Business.fromMongoDocument(d)).toList();
  }

  Future<void> upsertByPlaceId(Business business) async {
    if (business.placeId == null) {
      throw ArgumentError('Business must have a placeId for upsert');
    }

    final existing = await findByPlaceId(business.placeId!);
    final doc = business.toMongoDocument();

    if (existing == null) {
      // New business - get next sequence ID and set createdAt
      final nextId = await _getNextSequenceId();
      doc['sequenceId'] = nextId;
      doc['createdAt'] = DateTime.now();
      await _collection.insertOne(doc);
    } else {
      // Existing business - update, preserve createdAt
      doc.remove('createdAt');
      await _collection.updateOne(
        where.eq('placeId', business.placeId),
        {'\$set': doc},
      );
    }
  }

  Future<void> appendAirportCode(String placeId, String airportCode) async {
    final existing = await findByPlaceId(placeId);
    if (existing == null) return;

    final currentCodes = existing.airportCode ?? '';
    if (currentCodes.contains(airportCode)) return;

    final newCodes = currentCodes.isEmpty ? airportCode : '$currentCodes,$airportCode';
    await _collection.updateOne(
      where.eq('placeId', placeId),
      modify.set('airportCode', newCodes).set('updatedAt', DateTime.now()),
    );
  }

  Future<bool> needsRefresh(String placeId, {bool forceStale = false}) async {
    final existing = await findByPlaceId(placeId);
    if (existing == null) return true; // New business

    if (existing.ignore) return false; // Skip ignored

    final updatedAt = existing.updatedAt;
    if (updatedAt == null) return true;

    final daysSinceUpdate = DateTime.now().difference(updatedAt).inDays;
    if (daysSinceUpdate > 90) return true; // Stale data
    if (forceStale && daysSinceUpdate > 30) return true; // Optional refresh

    return false; // Use cached data
  }

  Future<int> count() async {
    return await _collection.count();
  }

  Future<int> countByAirportCode(String airportCode) async {
    return await _collection.count(where.eq('airportCode', airportCode));
  }

  Future<int> _getNextSequenceId() async {
    // Find the max sequenceId and increment
    final pipeline = [
      {
        '\$group': {
          '_id': null,
          'maxId': {'\$max': '\$sequenceId'},
        },
      },
    ];
    final result = await _collection.aggregateToStream(pipeline).toList();
    if (result.isEmpty || result.first['maxId'] == null) {
      return 1;
    }
    return (result.first['maxId'] as int) + 1;
  }
}
