import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/business.dart';
import '../utils/config.dart';

/// Dart 2.x-compatible firstOrNull for Iterable
T? _firstOrNull<T>(Iterable<T> iterable) {
  final iterator = iterable.iterator;
  return iterator.moveNext() ? iterator.current : null;
}

// Google Places API field lists
const _placesSearchBasicList = 'business_status,formatted_address,geometry,'
    'icon,name,permanently_closed,place_id,plus_code,types';
const _detailsSearchBasicList = 'address_component,adr_address,business_status,formatted_address,'
    'geometry,icon,name,permanently_closed,photo,place_id,plus_code,'
    'type,url,utc_offset,vicinity';
const _detailsSearchContactList = 'formatted_phone_number,'
    'international_phone_number,opening_hours,website';
const _detailsSearchAtmosphereList = 'price_level,rating,user_ratings_total';

class PlacesApi {
  final String apiKey;

  PlacesApi(this.apiKey);

  factory PlacesApi.fromConfig(Config config) => PlacesApi(config.googlePlacesApiKey);

  /// Search nearby for businesses matching a keyword around a lat/lng
  Future<NearbySearchResponse> searchNearby({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    required String keyword,
    String? pageToken,
  }) async {
    var url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
        'location=$latitude,$longitude&radius=$radiusMeters&keyword=$keyword&'
        'key=$apiKey';

    if (pageToken != null) {
      url += '&pagetoken=$pageToken';
    }

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      return NearbySearchResponse.fromJson(jsonDecode(response.body));
    }

    throw PlacesApiException(
      'Nearby search failed with status ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  /// Get full place details by Place ID
  Future<PlaceDetailsResult?> getPlaceDetails(String placeId) async {
    final url = 'https://maps.googleapis.com/maps/api/place/details/json?'
        'place_id=$placeId&fields=$_detailsSearchBasicList,'
        '$_detailsSearchContactList,$_detailsSearchAtmosphereList&key=$apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['result'] == null) return null;
      return PlaceDetailsResult.fromJson(json['result']);
    }

    throw PlacesApiException(
      'Place details failed with status ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  /// Convert miles to meters
  static int milesToMeters(double miles) => (miles * 1609.34).round();
}

/// Retry wrapper with exponential backoff
Future<T> withRetry<T>(
  Future<T> Function() apiCall, {
  int maxRetries = 3,
  Duration initialDelay = const Duration(seconds: 2),
}) async {
  int attempts = 0;
  while (true) {
    try {
      return await apiCall();
    } on PlacesApiException catch (e) {
      attempts++;
      if (attempts >= maxRetries) rethrow;

      if (e.statusCode == 429) {
        // Rate limited - exponential backoff
        final delay = Duration(seconds: math.pow(2, attempts).toInt());
        print('  Rate limited. Waiting ${delay.inSeconds}s (attempt $attempts/$maxRetries)...');
        await Future.delayed(delay);
      } else if (e.statusCode != null && e.statusCode! >= 500) {
        // Server error - fixed delay retry
        print('  Server error ${e.statusCode}. Retrying in 5s (attempt $attempts/$maxRetries)...');
        await Future.delayed(const Duration(seconds: 5));
      } else if (e.statusCode == 400) {
        // Bad request - don't retry
        print('  Bad request: ${e.message}');
        rethrow;
      } else if (e.statusCode == 401 || e.statusCode == 403) {
        // Auth error - abort
        print('  Authentication error: ${e.message}');
        rethrow;
      } else {
        rethrow;
      }
    } on Exception catch (e) {
      attempts++;
      if (attempts >= maxRetries) rethrow;
      print('  Network error: $e. Retrying in 5s (attempt $attempts/$maxRetries)...');
      await Future.delayed(const Duration(seconds: 5));
    }
  }
}

// ─── Response Models ────────────────────────────────────────────────────────

class NearbySearchResponse {
  final List<NearbyResult> results;
  final String? nextPageToken;
  final String status;

  NearbySearchResponse({
    required this.results,
    this.nextPageToken,
    required this.status,
  });

  factory NearbySearchResponse.fromJson(Map<String, dynamic> json) {
    final token = json['next_page_token'] as String?;
    return NearbySearchResponse(
      results: (json['results'] as List?)
              ?.map((r) => NearbyResult.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      nextPageToken: (token != null && token.isNotEmpty) ? token : null,
      status: json['status'] as String? ?? 'UNKNOWN',
    );
  }
}

class NearbyResult {
  final String? placeId;
  final String? name;
  final String? businessStatus;
  final String? vicinity;
  final String? icon;
  final double? lat;
  final double? lng;
  final double? rating;
  final int? userRatingsTotal;
  final List<String> types;
  final String? globalCode;
  final String? compoundCode;

  NearbyResult({
    this.placeId,
    this.name,
    this.businessStatus,
    this.vicinity,
    this.icon,
    this.lat,
    this.lng,
    this.rating,
    this.userRatingsTotal,
    this.types = const [],
    this.globalCode,
    this.compoundCode,
  });

  factory NearbyResult.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    final plusCode = json['plus_code'] as Map<String, dynamic>?;

    return NearbyResult(
      placeId: json['place_id'] as String?,
      name: json['name'] as String?,
      businessStatus: json['business_status'] as String?,
      vicinity: json['vicinity'] as String?,
      icon: json['icon'] as String?,
      lat: (location?['lat'] as num?)?.toDouble(),
      lng: (location?['lng'] as num?)?.toDouble(),
      rating: (json['rating'] as num?)?.toDouble(),
      userRatingsTotal: json['user_ratings_total'] as int?,
      types: (json['types'] as List?)?.cast<String>() ?? [],
      globalCode: plusCode?['global_code'] as String?,
      compoundCode: plusCode?['compound_code'] as String?,
    );
  }
}

class PlaceDetailsResult {
  final String? name;
  final String? placeId;
  final String? formattedAddress;
  final String? formattedPhoneNumber;
  final String? internationalPhoneNumber;
  final String? website;
  final String? url; // Google Maps URL
  final String? vicinity;
  final String? icon;
  final String? adrAddress;
  final double? rating;
  final int? userRatingsTotal;
  final int? utcOffset;
  final String? businessStatus;
  final List<AddressComponent> addressComponents;
  final double? lat;
  final double? lng;
  final String? globalCode;
  final String? compoundCode;
  final List<String> types;

  PlaceDetailsResult({
    this.name,
    this.placeId,
    this.formattedAddress,
    this.formattedPhoneNumber,
    this.internationalPhoneNumber,
    this.website,
    this.url,
    this.vicinity,
    this.icon,
    this.adrAddress,
    this.rating,
    this.userRatingsTotal,
    this.utcOffset,
    this.businessStatus,
    this.addressComponents = const [],
    this.lat,
    this.lng,
    this.globalCode,
    this.compoundCode,
    this.types = const [],
  });

  factory PlaceDetailsResult.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    final plusCode = json['plus_code'] as Map<String, dynamic>?;

    return PlaceDetailsResult(
      name: json['name'] as String?,
      placeId: json['place_id'] as String?,
      formattedAddress: json['formatted_address'] as String?,
      formattedPhoneNumber: json['formatted_phone_number'] as String?,
      internationalPhoneNumber: json['international_phone_number'] as String?,
      website: json['website'] as String?,
      url: json['url'] as String?,
      vicinity: json['vicinity'] as String?,
      icon: json['icon'] as String?,
      adrAddress: json['adr_address'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      userRatingsTotal: json['user_ratings_total'] as int?,
      utcOffset: json['utc_offset'] as int?,
      businessStatus: json['business_status'] as String?,
      addressComponents: (json['address_components'] as List?)
              ?.map((a) => AddressComponent.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      lat: (location?['lat'] as num?)?.toDouble(),
      lng: (location?['lng'] as num?)?.toDouble(),
      globalCode: plusCode?['global_code'] as String?,
      compoundCode: plusCode?['compound_code'] as String?,
      types: (json['types'] as List?)?.cast<String>() ?? [],
    );
  }

  /// Find the shortName of the first address component matching a type
  String? _componentShortName(String type) {
    final match = _firstOrNull(addressComponents.where((a) => a.types.contains(type)));
    return match?.shortName;
  }

  /// Extract street address from address components
  String get streetAddress {
    final streetNumber = _componentShortName('street_number');
    final route = _componentShortName('route');
    return '${streetNumber ?? ''} ${route ?? ''}'.trim();
  }

  String? get subpremise => _componentShortName('subpremise');

  String? get city {
    if (vicinity != null && vicinity!.contains(',')) {
      return vicinity!.substring(vicinity!.lastIndexOf(',') + 1).trim();
    }
    return _componentShortName('locality');
  }

  String? get state => _componentShortName('administrative_area_level_1');

  String? get postalCode {
    final zip = _componentShortName('postal_code');
    if (zip == null) return null;

    final suffix = _componentShortName('postal_code_suffix');
    return suffix != null ? '$zip-$suffix' : zip;
  }

  String? get countryCode => _componentShortName('country');

  /// Convert to a Business model for storage
  Business toBusiness({required String airportCode, String? searchKeyword}) {
    return Business(
      name: name,
      syncName: name,
      placeId: placeId,
      airportCode: airportCode,
      address: streetAddress.isNotEmpty ? streetAddress : null,
      addressTwo: subpremise,
      city: city,
      state: state,
      zipCode: postalCode,
      country: countryCode,
      mobileNo: formattedPhoneNumber,
      internationalNo: internationalPhoneNumber,
      websiteURL: website,
      businessUrl: website,
      mapUrl: url,
      fullAddress: formattedAddress,
      businessStatus: businessStatus,
      latitude: lat,
      longitude: lng,
      image: icon,
      vicinity: vicinity,
      rating: rating,
      businessReviewCount: userRatingsTotal,
      globalCode: globalCode,
      compoundCode: compoundCode,
      googleListingTypes: types.join(','),
      isGoogleData: 1,
      newData: true,
      searchTerms: searchKeyword,
    );
  }
}

class AddressComponent {
  final String? longName;
  final String? shortName;
  final List<String> types;

  AddressComponent({this.longName, this.shortName, this.types = const []});

  factory AddressComponent.fromJson(Map<String, dynamic> json) => AddressComponent(
        longName: json['long_name'] as String?,
        shortName: json['short_name'] as String?,
        types: (json['types'] as List?)?.cast<String>() ?? [],
      );
}

class PlacesApiException implements Exception {
  final String message;
  final int? statusCode;

  PlacesApiException(this.message, {this.statusCode});

  @override
  String toString() => 'PlacesApiException($statusCode): $message';
}
