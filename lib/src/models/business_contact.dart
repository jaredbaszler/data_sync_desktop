class BusinessContact {
  /// MongoDB ObjectId as string
  String? id;

  /// Reference to the business (placeId from avtopia_business)
  String? businessPlaceId;

  /// Contact's full name (first + last name)
  String? name;

  /// Contact's role (e.g., "Accountable Manager", "Liaison", "Agency")
  String? role;

  /// Contact's email address
  String? email;

  /// List of phone numbers with their types
  List<PhoneNumber>? phoneNumbers;

  /// Timestamp when this contact was created
  DateTime? createdAt;

  /// Timestamp when this contact was last updated
  DateTime? updatedAt;

  BusinessContact({
    this.id,
    this.businessPlaceId,
    this.name,
    this.role,
    this.email,
    this.phoneNumbers,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMongoDocument() {
    return {
      'businessPlaceId': businessPlaceId,
      'name': name,
      'role': role,
      'email': email,
      'phoneNumbers': phoneNumbers?.map((p) => p.toMap()).toList(),
      'createdAt': createdAt,
      'updatedAt': DateTime.now(),
    };
  }

  factory BusinessContact.fromMongoDocument(Map<String, dynamic> doc) {
    final phonesList = (doc['phoneNumbers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return BusinessContact(
      id: doc['_id']?.toString(),
      businessPlaceId: doc['businessPlaceId'] as String?,
      name: doc['name'] as String?,
      role: doc['role'] as String?,
      email: doc['email'] as String?,
      phoneNumbers: phonesList.map((p) => PhoneNumber.fromMap(p)).toList(),
      createdAt: doc['createdAt'] as DateTime?,
      updatedAt: doc['updatedAt'] as DateTime?,
    );
  }

  @override
  String toString() => 'BusinessContact($name, $role, $email)';
}

class PhoneNumber {
  /// Phone number value (e.g., "555-1234" or "+1-555-1234")
  String? number;

  /// Phone type: main, business, mobile, other
  String? type;

  PhoneNumber({
    this.number,
    this.type = 'main',
  });

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'type': type ?? 'main',
    };
  }

  factory PhoneNumber.fromMap(Map<String, dynamic> map) {
    return PhoneNumber(
      number: map['number'] as String?,
      type: map['type'] as String? ?? 'main',
    );
  }

  @override
  String toString() => '$number ($type)';
}
