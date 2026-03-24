class FarEntry {
  final String name;
  final String? dba1;
  final String? dba2;
  final String? dba3;
  final String? street1;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? airportCode;
  final List<String> dbCodes; // dbCode1 through dbCode5
  final String farType; // P135, FLT141, FLT142, P145, P147

  // Set after loading via geocoding; null until geocoded
  double? lat;
  double? lng;

  FarEntry({
    required this.name,
    this.dba1,
    this.dba2,
    this.dba3,
    this.street1,
    this.city,
    this.state,
    this.zipCode,
    this.airportCode,
    required this.dbCodes,
    required this.farType,
  });

  /// All name variants to match against (name + DBAs)
  List<String> get allNames => [
        name,
        if (dba1 != null && dba1!.isNotEmpty) dba1!,
        if (dba2 != null && dba2!.isNotEmpty) dba2!,
        if (dba3 != null && dba3!.isNotEmpty) dba3!,
      ];

  @override
  String toString() => 'FarEntry($name, $farType, $city, $state)';
}
