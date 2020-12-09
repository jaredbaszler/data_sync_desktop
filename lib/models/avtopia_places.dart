// To parse this JSON data, do
//
//     final avtopiaPlaces = avtopiaPlacesFromJson(jsonString);

import 'dart:convert';

AvtopiaPlaces avtopiaPlacesFromJson(String str) =>
    AvtopiaPlaces.fromJson(json.decode(str));

String avtopiaPlacesToJson(AvtopiaPlaces data) => json.encode(data.toJson());

class AvtopiaPlaces {
  AvtopiaPlaces({
    this.id,
    this.accountAccountName,
    this.accountDba1,
    this.accountDba2,
    this.accountDba3,
    this.accountShippingStreet1,
    this.accountShippingStreet2,
    this.accountShippingCity,
    this.accountShippingStateProvince,
    this.accountShippingZipPostalCode,
    this.accountShippingCountry,
    this.accountPhone,
    this.accountWebsite,
    this.busCategory1,
    this.busCategory2,
    this.busCategory3,
    this.busCategory4,
    this.busCategory5,
    this.busCategory6,
    this.busCategory7,
    this.busCategory8,
    this.busCategory9,
    this.busCategory10,
    this.tag1,
    this.tag2,
    this.tag3,
    this.tag4,
    this.tag5,
    this.tag6,
    this.tag7,
    this.tag8,
    this.tag9,
    this.tag10,
    this.tag11,
    this.tag12,
    this.tag13,
    this.tag14,
    this.tag15,
    this.tag16,
    this.tag17,
    this.tag18,
    this.tag19,
    this.tag20,
  });

  String id;
  String accountAccountName;
  String accountDba1;
  String accountDba2;
  String accountDba3;
  String accountShippingStreet1;
  String accountShippingStreet2;
  String accountShippingCity;
  String accountShippingStateProvince;
  String accountShippingZipPostalCode;
  String accountShippingCountry;
  String accountPhone;
  String accountWebsite;
  String busCategory1;
  String busCategory2;
  String busCategory3;
  String busCategory4;
  String busCategory5;
  String busCategory6;
  String busCategory7;
  String busCategory8;
  String busCategory9;
  String busCategory10;
  String tag1;
  String tag2;
  String tag3;
  String tag4;
  String tag5;
  String tag6;
  String tag7;
  String tag8;
  String tag9;
  String tag10;
  String tag11;
  String tag12;
  String tag13;
  String tag14;
  String tag15;
  String tag16;
  String tag17;
  String tag18;
  String tag19;
  String tag20;

  factory AvtopiaPlaces.fromJson(Map<String, dynamic> json) => AvtopiaPlaces(
        id: json["ID"],
        accountAccountName: json["Account: Account Name"],
        accountDba1: json["Account: DBA 1"],
        accountDba2: json["Account: DBA 2"],
        accountDba3: json["Account: DBA 3"],
        accountShippingStreet1: json["Account: Shipping Street 1"],
        accountShippingStreet2: json["Account: Shipping Street 2"],
        accountShippingCity: json["Account: Shipping City"],
        accountShippingStateProvince: json["Account:ShippingState/Province"],
        accountShippingZipPostalCode: json["Account: Shipping Zip/Postal Code"],
        accountShippingCountry: json["Account: Shipping Country"],
        accountPhone: json["Account: Phone"],
        accountWebsite: json["Account: Website"],
        busCategory1: json["Bus Category 1"],
        busCategory2: json["Bus Category 2"],
        busCategory3: json["Bus Category 3"],
        busCategory4: json["Bus Category 4"],
        busCategory5: json["Bus Category 5"],
        busCategory6: json["Bus Category 6"],
        busCategory7: json["Bus Category 7"],
        busCategory8: json["Bus Category 8"],
        busCategory9: json["Bus Category 9"],
        busCategory10: json["Bus Category 10"],
        tag1: json["TAG 1"],
        tag2: json["TAG 2"],
        tag3: json["TAG 3"],
        tag4: json["TAG 4"],
        tag5: json["TAG 5"],
        tag6: json["TAG 6"],
        tag7: json["TAG 7"],
        tag8: json["TAG 8"],
        tag9: json["TAG 9"],
        tag10: json["TAG 10"],
        tag11: json["TAG 11"],
        tag12: json["TAG 12"],
        tag13: json["TAG 13"],
        tag14: json["TAG 14"],
        tag15: json["TAG 15"],
        tag16: json["TAG 16"],
        tag17: json["TAG 17"],
        tag18: json["TAG 18"],
        tag19: json["TAG 19"],
        tag20: json["TAG 20"],
      );

  Map<String, dynamic> toJson() => {
        "ID": id,
        "Account: Account Name": accountAccountName,
        "Account: DBA 1": accountDba1,
        "Account: DBA 2": accountDba2,
        "Account: DBA 3": accountDba3,
        "Account: Shipping Street 1": accountShippingStreet1,
        "Account: Shipping Street 2": accountShippingStreet2,
        "Account: Shipping City": accountShippingCity,
        "Account:ShippingState/Province": accountShippingStateProvince,
        "Account: Shipping Zip/Postal Code": accountShippingZipPostalCode,
        "Account: Shipping Country": accountShippingCountry,
        "Account: Phone": accountPhone,
        "Account: Website": accountWebsite,
        "Bus Category 1": busCategory1,
        "Bus Category 2": busCategory2,
        "Bus Category 3": busCategory3,
        "Bus Category 4": busCategory4,
        "Bus Category 5": busCategory5,
        "Bus Category 6": busCategory6,
        "Bus Category 7": busCategory7,
        "Bus Category 8": busCategory8,
        "Bus Category 9": busCategory9,
        "Bus Category 10": busCategory10,
        "TAG 1": tag1,
        "TAG 2": tag2,
        "TAG 3": tag3,
        "TAG 4": tag4,
        "TAG 5": tag5,
        "TAG 6": tag6,
        "TAG 7": tag7,
        "TAG 8": tag8,
        "TAG 9": tag9,
        "TAG 10": tag10,
        "TAG 11": tag11,
        "TAG 12": tag12,
        "TAG 13": tag13,
        "TAG 14": tag14,
        "TAG 15": tag15,
        "TAG 16": tag16,
        "TAG 17": tag17,
        "TAG 18": tag18,
        "TAG 19": tag19,
        "TAG 20": tag20,
      };
}
