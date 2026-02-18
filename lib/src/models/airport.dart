class Airport {
  final String icaoCode;
  final String? iataCode;
  final String? faaCode;
  final String? gpsCode;
  final String name;
  final String? state;
  final String? country;
  final double latitude;
  final double longitude;
  final bool sixtyPlusAirport;
  final bool enabled;
  final DateTime? lastProcessed;
  final DateTime createdAt;
  final DateTime updatedAt;

  Airport({
    required this.icaoCode,
    this.iataCode,
    this.faaCode,
    this.gpsCode,
    required this.name,
    this.state,
    this.country,
    required this.latitude,
    required this.longitude,
    this.sixtyPlusAirport = false,
    this.enabled = true,
    this.lastProcessed,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMongoDocument() => {
        '_id': icaoCode,
        'icaoCode': icaoCode,
        'iataCode': iataCode,
        'faaCode': faaCode,
        'gpsCode': gpsCode,
        'name': name,
        'state': state,
        'country': country,
        'latitude': latitude,
        'longitude': longitude,
        'sixtyPlusAirport': sixtyPlusAirport,
        'enabled': enabled,
        'lastProcessed': lastProcessed,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory Airport.fromMongoDocument(Map<String, dynamic> doc) => Airport(
        icaoCode: doc['_id'] as String? ?? doc['icaoCode'] as String,
        iataCode: doc['iataCode'] as String?,
        faaCode: doc['faaCode'] as String?,
        gpsCode: doc['gpsCode'] as String?,
        name: doc['name'] as String? ?? '',
        state: doc['state'] as String?,
        country: doc['country'] as String?,
        latitude: (doc['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (doc['longitude'] as num?)?.toDouble() ?? 0.0,
        sixtyPlusAirport: doc['sixtyPlusAirport'] as bool? ?? false,
        enabled: doc['enabled'] as bool? ?? true,
        lastProcessed: doc['lastProcessed'] as DateTime?,
        createdAt: doc['createdAt'] as DateTime?,
        updatedAt: doc['updatedAt'] as DateTime?,
      );

  @override
  String toString() => 'Airport($icaoCode - $name)';
}
