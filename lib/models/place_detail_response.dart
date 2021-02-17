// To parse this JSON data, do
//
//     final placeDetailResponse = placeDetailResponseFromJson(jsonString);

import 'dart:convert';

PlaceDetailResponse placeDetailResponseFromJson(String str) =>
    PlaceDetailResponse.fromJson(json.decode(str));

String placeDetailResponseToJson(PlaceDetailResponse data) =>
    json.encode(data.toJson());

class PlaceDetailResponse {
  PlaceDetailResponse({
    this.htmlAttributions,
    this.result,
    this.status,
  });

  List<dynamic> htmlAttributions;
  Result result;
  String status;

  factory PlaceDetailResponse.fromJson(Map<String, dynamic> json) =>
      PlaceDetailResponse(
        htmlAttributions: json["html_attributions"] == null
            ? null
            : List<dynamic>.from(json["html_attributions"].map((x) => x)),
        result: json["result"] == null ? null : Result.fromJson(json["result"]),
        status: json["status"] == null ? null : json["status"],
      );

  Map<String, dynamic> toJson() => {
        "html_attributions": htmlAttributions == null
            ? null
            : List<dynamic>.from(htmlAttributions.map((x) => x)),
        "result": result == null ? null : result.toJson(),
        "status": status == null ? null : status,
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
        addressComponents: json["address_components"] == null
            ? null
            : List<AddressComponent>.from(json["address_components"]
                .map((x) => AddressComponent.fromJson(x))),
        adrAddress: json["adr_address"] == null ? null : json["adr_address"],
        formattedAddress: json["formatted_address"] == null
            ? null
            : json["formatted_address"],
        formattedPhoneNumber: json["formatted_phone_number"] == null
            ? null
            : json["formatted_phone_number"],
        geometry: json["geometry"] == null
            ? null
            : Geometry.fromJson(json["geometry"]),
        icon: json["icon"] == null ? null : json["icon"],
        id: json["id"] == null ? null : json["id"],
        internationalPhoneNumber: json["international_phone_number"] == null
            ? null
            : json["international_phone_number"],
        name: json["name"] == null ? null : json["name"],
        placeId: json["place_id"] == null ? null : json["place_id"],
        rating: json["rating"] == null ? null : json["rating"].toDouble(),
        reference: json["reference"] == null ? null : json["reference"],
        reviews: json["reviews"] == null
            ? null
            : List<Review>.from(json["reviews"].map((x) => Review.fromJson(x))),
        types: json["types"] == null
            ? null
            : List<String>.from(json["types"].map((x) => x)),
        url: json["url"] == null ? null : json["url"],
        utcOffset: json["utc_offset"] == null ? null : json["utc_offset"],
        vicinity: json["vicinity"] == null ? null : json["vicinity"],
        website: json["website"] == null ? null : json["website"],
      );

  Map<String, dynamic> toJson() => {
        "address_components": addressComponents == null
            ? null
            : List<dynamic>.from(addressComponents.map((x) => x.toJson())),
        "adr_address": adrAddress == null ? null : adrAddress,
        "formatted_address": formattedAddress == null ? null : formattedAddress,
        "formatted_phone_number":
            formattedPhoneNumber == null ? null : formattedPhoneNumber,
        "geometry": geometry == null ? null : geometry.toJson(),
        "icon": icon == null ? null : icon,
        "id": id == null ? null : id,
        "international_phone_number":
            internationalPhoneNumber == null ? null : internationalPhoneNumber,
        "name": name == null ? null : name,
        "place_id": placeId == null ? null : placeId,
        "rating": rating == null ? null : rating,
        "reference": reference == null ? null : reference,
        "reviews": reviews == null
            ? null
            : List<dynamic>.from(reviews.map((x) => x.toJson())),
        "types": types == null ? null : List<dynamic>.from(types.map((x) => x)),
        "url": url == null ? null : url,
        "utc_offset": utcOffset == null ? null : utcOffset,
        "vicinity": vicinity == null ? null : vicinity,
        "website": website == null ? null : website,
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
        longName: json["long_name"] == null ? null : json["long_name"],
        shortName: json["short_name"] == null ? null : json["short_name"],
        types: json["types"] == null
            ? null
            : List<String>.from(json["types"].map((x) => x)),
      );

  Map<String, dynamic> toJson() => {
        "long_name": longName == null ? null : longName,
        "short_name": shortName == null ? null : shortName,
        "types": types == null ? null : List<dynamic>.from(types.map((x) => x)),
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
        location: json["location"] == null
            ? null
            : Location.fromJson(json["location"]),
        viewport: json["viewport"] == null
            ? null
            : Viewport.fromJson(json["viewport"]),
      );

  Map<String, dynamic> toJson() => {
        "location": location == null ? null : location.toJson(),
        "viewport": viewport == null ? null : viewport.toJson(),
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
        lat: json["lat"] == null ? null : json["lat"].toDouble(),
        lng: json["lng"] == null ? null : json["lng"].toDouble(),
      );

  Map<String, dynamic> toJson() => {
        "lat": lat == null ? null : lat,
        "lng": lng == null ? null : lng,
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
        northeast: json["northeast"] == null
            ? null
            : Location.fromJson(json["northeast"]),
        southwest: json["southwest"] == null
            ? null
            : Location.fromJson(json["southwest"]),
      );

  Map<String, dynamic> toJson() => {
        "northeast": northeast == null ? null : northeast.toJson(),
        "southwest": southwest == null ? null : southwest.toJson(),
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
        authorName: json["author_name"] == null ? null : json["author_name"],
        authorUrl: json["author_url"] == null ? null : json["author_url"],
        language: json["language"] == null ? null : json["language"],
        profilePhotoUrl: json["profile_photo_url"] == null
            ? null
            : json["profile_photo_url"],
        rating: json["rating"] == null ? null : json["rating"],
        relativeTimeDescription: json["relative_time_description"] == null
            ? null
            : json["relative_time_description"],
        text: json["text"] == null ? null : json["text"],
        time: json["time"] == null ? null : json["time"],
      );

  Map<String, dynamic> toJson() => {
        "author_name": authorName == null ? null : authorName,
        "author_url": authorUrl == null ? null : authorUrl,
        "language": language == null ? null : language,
        "profile_photo_url": profilePhotoUrl == null ? null : profilePhotoUrl,
        "rating": rating == null ? null : rating,
        "relative_time_description":
            relativeTimeDescription == null ? null : relativeTimeDescription,
        "text": text == null ? null : text,
        "time": time == null ? null : time,
      };
}
