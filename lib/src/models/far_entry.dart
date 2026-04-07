class FarEntry {
  final String name;
  final String? dba1;
  final String? dba2;
  final String? dba3;
  final String? street1;
  final String? street2;
  final String? street3;
  final String? city;
  final String? state;
  final String? country;
  final String? zipCode;
  final String? airportCode;
  final List<String> dbCodes; // dbCode1 through dbCode5 (or more if comma-delimited in last)
  final String farType; // P135, FLT141, FLT142, P145, P147
  final String? certNo; // Certificate number (FAA 145 only, used for syncName)
  final List<FarContact>? contacts; // FAA 145 contact info

  // Set after loading via geocoding; null until geocoded
  double? lat;
  double? lng;

  FarEntry({
    required this.name,
    this.dba1,
    this.dba2,
    this.dba3,
    this.street1,
    this.street2,
    this.street3,
    this.city,
    this.state,
    this.country,
    this.zipCode,
    this.airportCode,
    required this.dbCodes,
    required this.farType,
    this.certNo,
    this.contacts,
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

/// Contact information from FAA 145 repair station record
class FarContact {
  final String? name; // First + last name
  final String? role; // Agency, Accountable Manager, Liaison
  final String? email;
  final List<String>? phoneNumbers; // List of phone numbers

  FarContact({
    this.name,
    this.role,
    this.email,
    this.phoneNumbers,
  });

  @override
  String toString() => 'FarContact($name, $role)';
}
