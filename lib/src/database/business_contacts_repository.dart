import 'package:mongo_dart/mongo_dart.dart';

import '../models/business_contact.dart';
import 'mongodb_client.dart';

class BusinessContactsRepository {
  final MongoDbClient _client;
  final String collectionName;

  BusinessContactsRepository(this._client,
      {this.collectionName = 'avtopia_business_contact'});

  DbCollection get _collection => _client.collection(collectionName);

  Future<void> ensureIndexes() async {
    try {
      // Index on businessPlaceId for quick lookups
      await _collection.createIndex(keys: {'businessPlaceId': 1});
      // Index on updatedAt for maintenance queries
      await _collection.createIndex(keys: {'updatedAt': 1});
    } catch (e) {
      print('WARNING: Could not create indexes on $collectionName: $e');
    }
  }

  /// Find all contacts for a given business
  Future<List<BusinessContact>> findByBusinessPlaceId(String placeId) async {
    final docs = await _collection
        .find(where.eq('businessPlaceId', placeId))
        .toList();
    return docs.map((d) => BusinessContact.fromMongoDocument(d)).toList();
  }

  /// Insert a single contact
  Future<String> insertOne(BusinessContact contact) async {
    if (contact.businessPlaceId == null || contact.businessPlaceId!.isEmpty) {
      throw ArgumentError('Contact must have a businessPlaceId');
    }

    final doc = contact.toMongoDocument();
    doc['createdAt'] = DateTime.now();
    final result = await _collection.insertOne(doc);
    return result.id.toString();
  }

  /// Insert multiple contacts for a business (batch operation)
  Future<void> insertMany(List<BusinessContact> contacts) async {
    if (contacts.isEmpty) return;

    final docs = contacts.map((c) {
      final doc = c.toMongoDocument();
      doc['createdAt'] = DateTime.now();
      return doc;
    }).toList();

    await _collection.insertAll(docs);
  }

  /// Delete all contacts for a business (when removing a business)
  Future<int> deleteByBusinessPlaceId(String placeId) async {
    await _collection.deleteMany(where.eq('businessPlaceId', placeId));
    return 0; // mongo_dart doesn't return count, but operation succeeded
  }

  /// Update a single contact
  Future<void> updateOne(BusinessContact contact) async {
    if (contact.id == null) {
      throw ArgumentError('Contact must have an id to update');
    }

    final doc = contact.toMongoDocument();
    await _collection.updateOne(
      where.eq('_id', ObjectId.fromHexString(contact.id!)),
      {'\$set': doc},
    );
  }

  /// Count total contacts
  Future<int> count() async {
    return await _collection.count();
  }

  /// Count contacts for a specific business
  Future<int> countByBusinessPlaceId(String placeId) async {
    return await _collection.count(where.eq('businessPlaceId', placeId));
  }
}
