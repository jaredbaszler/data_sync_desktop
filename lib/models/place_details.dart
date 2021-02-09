// To parse this JSON data, do
//
//     final placeDetails = placeDetailsFromJson(jsonString);

import 'dart:convert';

PlaceDetails placeDetailsFromJson(String str) =>
    PlaceDetails.fromJson(json.decode(str));

String placeDetailsToJson(PlaceDetails data) => json.encode(data.toJson());

class PlaceDetails {
  PlaceDetails({
    this.htmlAttributions,
    this.result,
    this.status,
  });

  List<dynamic> htmlAttributions;
  Result result;
  String status;

  factory PlaceDetails.fromJson(Map<String, dynamic> json) => PlaceDetails(
        htmlAttributions:
            List<dynamic>.from(json["html_attributions"].map((x) => x)),
        result: Result.fromJson(json["result"]),
        status: json["status"],
      );

  Map<String, dynamic> toJson() => {
        "html_attributions": List<dynamic>.from(htmlAttributions.map((x) => x)),
        "result": result.toJson(),
        "status": status,
      };
}

class Result {
  Result({
    this.addressComponents,
    this.adrAddress,
    this.formattedAddress,
    this.formattedPhoneNumber,
    this.geometry,
    this.icon,
    this.id,
    this.internationalPhoneNumber,
    this.name,
    this.placeId,
    this.rating,
    this.reference,
    this.reviews,
    this.types,
    this.url,
    this.utcOffset,
    this.vicinity,
    this.website,
  });

  List<AddressComponent> addressComponents;
  String adrAddress;
  String formattedAddress;
  String formattedPhoneNumber;
  Geometry geometry;
  String icon;
  String id;
  String internationalPhoneNumber;
  String name;
  String placeId;
  double rating;
  String reference;
  List<Review> reviews;
  List<String> types;
  String url;
  int utcOffset;
  String vicinity;
  String website;

  factory Result.fromJson(Map<String, dynamic> json) => Result(
        addressComponents: List<AddressComponent>.from(
            json["address_components"]
                .map((x) => AddressComponent.fromJson(x))),
        adrAddress: json["adr_address"],
        formattedAddress: json["formatted_address"],
        formattedPhoneNumber: json["formatted_phone_number"],
        geometry: Geometry.fromJson(json["geometry"]),
        icon: json["icon"],
        id: json["id"],
        internationalPhoneNumber: json["international_phone_number"],
        name: json["name"],
        placeId: json["place_id"],
        rating: json["rating"].toDouble(),
        reference: json["reference"],
        reviews:
            List<Review>.from(json["reviews"].map((x) => Review.fromJson(x))),
        types: List<String>.from(json["types"].map((x) => x)),
        url: json["url"],
        utcOffset: json["utc_offset"],
        vicinity: json["vicinity"],
        website: json["website"],
      );

  Map<String, dynamic> toJson() => {
        "address_components":
            List<dynamic>.from(addressComponents.map((x) => x.toJson())),
        "adr_address": adrAddress,
        "formatted_address": formattedAddress,
        "formatted_phone_number": formattedPhoneNumber,
        "geometry": geometry.toJson(),
        "icon": icon,
        "id": id,
        "international_phone_number": internationalPhoneNumber,
        "name": name,
        "place_id": placeId,
        "rating": rating,
        "reference": reference,
        "reviews": List<dynamic>.from(reviews.map((x) => x.toJson())),
        "types": List<dynamic>.from(types.map((x) => x)),
        "url": url,
        "utc_offset": utcOffset,
        "vicinity": vicinity,
        "website": website,
      };
}

class AddressComponent {
  AddressComponent({
    this.longName,
    this.shortName,
    this.types,
  });

  String longName;
  String shortName;
  List<String> types;

  factory AddressComponent.fromJson(Map<String, dynamic> json) =>
      AddressComponent(
        longName: json["long_name"],
        shortName: json["short_name"],
        types: List<String>.from(json["types"].map((x) => x)),
      );

  Map<String, dynamic> toJson() => {
        "long_name": longName,
        "short_name": shortName,
        "types": List<dynamic>.from(types.map((x) => x)),
      };
}

class Geometry {
  Geometry({
    this.location,
    this.viewport,
  });

  Location location;
  Viewport viewport;

  factory Geometry.fromJson(Map<String, dynamic> json) => Geometry(
        location: Location.fromJson(json["location"]),
        viewport: Viewport.fromJson(json["viewport"]),
      );

  Map<String, dynamic> toJson() => {
        "location": location.toJson(),
        "viewport": viewport.toJson(),
      };
}

class Location {
  Location({
    this.lat,
    this.lng,
  });

  double lat;
  double lng;

  factory Location.fromJson(Map<String, dynamic> json) => Location(
        lat: json["lat"].toDouble(),
        lng: json["lng"].toDouble(),
      );

  Map<String, dynamic> toJson() => {
        "lat": lat,
        "lng": lng,
      };
}

class Viewport {
  Viewport({
    this.northeast,
    this.southwest,
  });

  Location northeast;
  Location southwest;

  factory Viewport.fromJson(Map<String, dynamic> json) => Viewport(
        northeast: Location.fromJson(json["northeast"]),
        southwest: Location.fromJson(json["southwest"]),
      );

  Map<String, dynamic> toJson() => {
        "northeast": northeast.toJson(),
        "southwest": southwest.toJson(),
      };
}

class Review {
  Review({
    this.authorName,
    this.authorUrl,
    this.language,
    this.profilePhotoUrl,
    this.rating,
    this.relativeTimeDescription,
    this.text,
    this.time,
  });

  String authorName;
  String authorUrl;
  String language;
  String profilePhotoUrl;
  int rating;
  String relativeTimeDescription;
  String text;
  int time;

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        authorName: json["author_name"],
        authorUrl: json["author_url"],
        language: json["language"],
        profilePhotoUrl: json["profile_photo_url"],
        rating: json["rating"],
        relativeTimeDescription: json["relative_time_description"],
        text: json["text"],
        time: json["time"],
      );

  Map<String, dynamic> toJson() => {
        "author_name": authorName,
        "author_url": authorUrl,
        "language": language,
        "profile_photo_url": profilePhotoUrl,
        "rating": rating,
        "relative_time_description": relativeTimeDescription,
        "text": text,
        "time": time,
      };
}
