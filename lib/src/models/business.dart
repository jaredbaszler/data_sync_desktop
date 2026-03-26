class Business {
  String? name;
  String? dba1;
  String? dba2;
  String? dba3;
  String? address;
  String? addressTwo;
  String? city;
  String? state;
  String? zipCode;
  String? country;
  String? mobileNo;
  String? websiteURL;
  String? airportCode;
  bool ignore;
  bool manual;
  String? placeId;
  String? syncName;
  String? businessStatus;
  String? fullAddress;
  double? latitude;
  double? longitude;
  String? vicinity;
  String? businessUrl;
  String? mapUrl;
  String? image;
  double? rating;
  int? businessReviewCount;
  String? globalCode;
  String? compoundCode;
  String? internationalNo;
  String? formattedPhoneNumber;
  int? isGoogleData;
  bool? newData;
  DateTime? createdAt;
  DateTime? updatedAt;
  int? sequenceId;

  // Categorization fields
  String? dbCode;
  String? dbCode3;
  String? dbCode4;
  String? dbCode5;
  String? searchValue1;
  String? searchValue2;
  String? searchValue3;
  String? searchValue4;
  String? searchValue5;

  // Search tracking
  String? searchTerms;

  // Google listing types
  String? googleListingTypes;

  Business({
    this.name,
    this.dba1,
    this.dba2,
    this.dba3,
    this.address,
    this.addressTwo,
    this.city,
    this.state,
    this.zipCode,
    this.country,
    this.mobileNo,
    this.websiteURL,
    this.airportCode,
    this.ignore = false,
    this.manual = false,
    this.placeId,
    this.syncName,
    this.businessStatus,
    this.fullAddress,
    this.latitude,
    this.longitude,
    this.vicinity,
    this.businessUrl,
    this.mapUrl,
    this.image,
    this.rating,
    this.businessReviewCount,
    this.globalCode,
    this.compoundCode,
    this.internationalNo,
    this.formattedPhoneNumber,
    this.isGoogleData,
    this.newData,
    this.createdAt,
    this.updatedAt,
    this.sequenceId,
    this.dbCode,
    this.dbCode3,
    this.dbCode4,
    this.dbCode5,
    this.searchValue1,
    this.searchValue2,
    this.searchValue3,
    this.searchValue4,
    this.searchValue5,
    this.searchTerms,
    this.googleListingTypes,
  });

  Map<String, dynamic> toMongoDocument() {
    final doc = <String, dynamic>{
      'name': name,
      'dba1': dba1,
      'dba2': dba2,
      'dba3': dba3,
      'address': address,
      'addressTwo': addressTwo,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'country': country,
      'mobileNo': mobileNo,
      'websiteURL': websiteURL,
      'airportCode': airportCode,
      'ignore': ignore,
      'manual': manual,
      'placeId': placeId,
      'syncName': syncName,
      'businessStatus': businessStatus,
      'fullAddress': fullAddress,
      'vicinity': vicinity,
      'businessUrl': businessUrl,
      'mapUrl': mapUrl,
      'image': image,
      'rating': rating,
      'businessReviewCount': businessReviewCount,
      'globalCode': globalCode,
      'compoundCode': compoundCode,
      'internationalNo': internationalNo,
      'formattedPhoneNumber': formattedPhoneNumber,
      'isGoogleData': isGoogleData ?? 1,
      'newData': newData ?? true,
      'updatedAt': DateTime.now(),
      'dbCode': dbCode,
      'dbCode3': dbCode3,
      'dbCode4': dbCode4,
      'dbCode5': dbCode5,
      'searchValue1': searchValue1,
      'searchValue2': searchValue2,
      'searchValue3': searchValue3,
      'searchValue4': searchValue4,
      'searchValue5': searchValue5,
      'searchTerms': searchTerms,
      'googleListingTypes': googleListingTypes,
    };

    // GeoJSON location format [lng, lat]
    if (latitude != null && longitude != null) {
      doc['location'] = {
        'address': fullAddress ?? '',
        'coordinates': [longitude!, latitude!],
      };
    }

    return doc;
  }

  factory Business.fromMongoDocument(Map<String, dynamic> doc) {
    double? lat;
    double? lng;

    final location = doc['location'];
    if (location is Map<String, dynamic>) {
      final coords = location['coordinates'];
      if (coords is List && coords.length >= 2) {
        lng = (coords[0] as num?)?.toDouble();
        lat = (coords[1] as num?)?.toDouble();
      }
    }

    return Business(
      name: doc['name'] as String?,
      dba1: doc['dba1'] as String?,
      dba2: doc['dba2'] as String?,
      dba3: doc['dba3'] as String?,
      address: doc['address'] as String?,
      addressTwo: doc['addressTwo'] as String?,
      city: doc['city'] as String?,
      state: doc['state'] as String?,
      zipCode: doc['zipCode']?.toString(),
      country: doc['country'] as String?,
      mobileNo: doc['mobileNo'] as String?,
      websiteURL: doc['websiteURL'] as String?,
      airportCode: doc['airportCode'] as String?,
      ignore: doc['ignore'] as bool? ?? false,
      manual: doc['manual'] as bool? ?? false,
      placeId: doc['placeId'] as String?,
      syncName: doc['syncName'] as String?,
      businessStatus: doc['businessStatus'] as String?,
      fullAddress: doc['fullAddress'] as String?,
      latitude: lat,
      longitude: lng,
      vicinity: doc['vicinity'] as String?,
      businessUrl: doc['businessUrl'] as String?,
      mapUrl: doc['mapUrl'] as String?,
      image: doc['image'] as String?,
      rating: (doc['rating'] as num?)?.toDouble(),
      businessReviewCount: doc['businessReviewCount'] as int?,
      globalCode: doc['globalCode'] as String?,
      compoundCode: doc['compoundCode'] as String?,
      internationalNo: doc['internationalNo'] as String?,
      formattedPhoneNumber: doc['formattedPhoneNumber'] as String?,
      isGoogleData: doc['isGoogleData'] as int?,
      newData: doc['newData'] as bool?,
      createdAt: doc['createdAt'] as DateTime?,
      updatedAt: doc['updatedAt'] as DateTime?,
      sequenceId: doc['sequenceId'] as int?,
      dbCode: doc['dbCode'] as String?,
      dbCode3: doc['dbCode3'] as String?,
      dbCode4: doc['dbCode4'] as String?,
      dbCode5: doc['dbCode5'] as String?,
      searchValue1: doc['searchValue1'] as String?,
      searchValue2: doc['searchValue2'] as String?,
      searchValue3: doc['searchValue3'] as String?,
      searchValue4: doc['searchValue4'] as String?,
      searchValue5: doc['searchValue5'] as String?,
      searchTerms: doc['searchTerms'] as String?,
      googleListingTypes: doc['googleListingTypes'] as String?,
    );
  }

  @override
  String toString() => 'Business(${name ?? "unnamed"}, placeId: $placeId, airport: $airportCode)';
}
