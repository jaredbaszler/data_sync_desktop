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

  /// Find all contacts for a given business by placeId
  Future<List<BusinessContact>> findByBusinessPlaceId(String placeId) async {
    final docs = await _collection
        .find(where.eq('businessPlaceId', placeId))
        .toList();
    return docs.map((d) => BusinessContact.fromMongoDocument(d)).toList();
  }

  /// Find all contacts for a given business by sequenceId (for non-Google imports)
  Future<List<BusinessContact>> findByBusinessSequenceId(int sequenceId) async {
    final docs = await _collection
        .find(where.eq('businessSequenceId', sequenceId))
        .toList();
    return docs.map((d) => BusinessContact.fromMongoDocument(d)).toList();
  }

  /// Insert a single contact. Must have either businessPlaceId or businessSequenceId.
  Future<String> insertOne(BusinessContact contact, {int? businessSequenceId}) async {
    final hasPlaceId = contact.businessPlaceId != null && contact.businessPlaceId!.isNotEmpty;
    final hasSeqId = businessSequenceId != null;
    if (!hasPlaceId && !hasSeqId) {
      throw ArgumentError('Contact must have a businessPlaceId or businessSequenceId');
    }

    final doc = contact.toMongoDocument();
    doc['createdAt'] = DateTime.now();
    if (businessSequenceId != null) doc['businessSequenceId'] = businessSequenceId;
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
