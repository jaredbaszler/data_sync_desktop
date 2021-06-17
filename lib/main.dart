import 'dart:convert';
import 'dart:io';

import 'package:data_sync_desktop/models/google_candidates.dart';
import 'package:data_sync_desktop/models/candidates.dart';
import 'package:data_sync_desktop/utils/extensions.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';

const apiKey = 'AIzaSyAUoR1hu32epmid_r-h7_AiXQWhNu3zr3U';
const basicGoogleFieldList = 'business_status,formatted_address,geometry,'
    'icon,name,permanently_closed,place_id,plus_code,types';
const originalDataColStart = 0;
const originalDataColEnd = 42;

Data cellByIndex(Sheet writeSheet, int rowIndex, int colIndex) {
  Data returnCell;

  for (final cell in writeSheet.row(rowIndex)) {
    if (cell.colIndex == colIndex) {
      returnCell = cell;
      break;
    }
  }

  return returnCell;
}

void updateByIndex(
    Sheet writeSheet, int rowIndex, int colIndex, String updateValue) {
  cellByIndex(writeSheet, rowIndex, colIndex)?.value = updateValue;
}

void copyCell(Sheet writeSheet, Sheet readSheet, int rowIndex, int colIndex) {
  writeSheet
          .cell(CellIndex.indexByColumnRow(
              rowIndex: rowIndex, columnIndex: colIndex))
          .value =
      readSheet
          .cell(CellIndex.indexByColumnRow(
              rowIndex: rowIndex, columnIndex: colIndex))
          .value;
}

void copyRow(Sheet writeSheet, Sheet readSheet, int rowIndex) {
  // *** upper bound here is hard-coded ***
  for (var colIndex = 0; colIndex <= AvtopiaCols.website; colIndex++) {
    copyCell(writeSheet, readSheet, rowIndex, colIndex);
  }
}

Future<bool> searchByNameAndAddress(
    Sheet writeSheet, Sheet readSheet, int rowIndex) async {
  final companyNameCell =
      cellByIndex(writeSheet, rowIndex, AvtopiaCols.accountName);
  final shipStreet1Cell =
      cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipStreet1);
  final shipStreet2Cell =
      cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipStreet2);
  final shipCityCell = cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipCity);
  final shipStateCell =
      cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipState);
  final shipZipCell = cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipZip);

  final searchString = '${companyNameCell.value} ${shipStreet1Cell.value} '
      '${shipStreet2Cell.value} ${shipCityCell.value} '
      '${shipStateCell.value} ${shipZipCell.value}';

  final searchUrl = googleByNameAndAddressURL(searchString: searchString);

  final response = await http.get(searchUrl);
  GoogleCandidates listOfCandidates;

  print('Searching name and address ($searchString} at URL:$searchUrl');

  if (response.statusCode == 200) {
    // TODO: check status returned for 'invalid_request' or anything other than OK
    // TODO: check 'types' in canidate return to look for 'premise' as that seems to just denote the address exists, need to view ""
    listOfCandidates = GoogleCandidates.fromJson(jsonDecode(response.body));
    if (listOfCandidates.candidates.isNotEmpty) {
      // Copy this row into the new file
      copyRow(writeSheet, readSheet, rowIndex);
    } else {
      return false; // return false if nothing is found
    }
  } else {
    print('Request failed with status: ${response.statusCode}.');
    return false;
  }

  for (final candidate in listOfCandidates.candidates) {
    var validMatch = true;

    if (!(candidate.types.contains('point_of_interest') ||
        candidate.types.contains('establishment'))) {
      validMatch = false;
    }
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.syncStatus))
        .value = validMatch ? 'YES' : 'NO';
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex,
            columnIndex: WriteCols.googleSyncByNameAndAddress))
        .value = validMatch ? 'X' : '';
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleURL))
        .value = searchUrl;

    if (validMatch) {
      writeGoogleCanidateInfo(candidate, writeSheet, readSheet, rowIndex);
    }
  }

  return true;
}

Future<bool> searchByPhone(
    Sheet writeSheet, Sheet readSheet, int rowIndex) async {
  // Transform the phone number
  final phoneCell = cellByIndex(writeSheet, rowIndex, AvtopiaCols.phone);
  final countryCell =
      cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipCountry);

  final byPhoneUrl = googleByPhoneURL(
      phoneNumber:
          phoneCell.value.toString().toIntlPhoneFormat(countryCell.value));

  print('Searching phone number ${phoneCell.value} at URL:$byPhoneUrl');

  final response = await http.get(byPhoneUrl);
  GoogleCandidates listOfCandidates;

  if (response.statusCode == 200) {
    listOfCandidates = GoogleCandidates.fromJson(jsonDecode(response.body));
    if (listOfCandidates.candidates.isNotEmpty) {
      // Copy this row into the new file
      copyRow(writeSheet, readSheet, rowIndex);
    } else {
      return false; // return false if nothing is found
    }
  } else {
    print('Request failed with status: ${response.statusCode}.');
    return false;
  }

  for (final candidate in listOfCandidates.candidates) {
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.syncStatus))
        .value = 'YES';
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleSyncByPhone))
        .value = 'X';
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleURL))
        .value = byPhoneUrl;

    writeGoogleCanidateInfo(candidate, writeSheet, readSheet, rowIndex);
  }

  return true;
}

void writeGoogleCanidateInfo(
    Candidates candidate, Sheet writeSheet, Sheet readSheet, int rowIndex) {
  writeSheet
      .cell(CellIndex.indexByColumnRow(
          rowIndex: rowIndex, columnIndex: WriteCols.googleJSON))
      .value = jsonEncode(candidate).toString();
  writeSheet
      .cell(CellIndex.indexByColumnRow(
          rowIndex: rowIndex, columnIndex: WriteCols.googleCompanyName))
      .value = candidate.name;
  writeSheet
      .cell(CellIndex.indexByColumnRow(
          rowIndex: rowIndex, columnIndex: WriteCols.googleBusinessStatus))
      .value = candidate.businessStatus;
  writeSheet
      .cell(CellIndex.indexByColumnRow(
          rowIndex: rowIndex, columnIndex: WriteCols.googlePlaceID))
      .value = candidate.placeId;
  writeSheet
      .cell(CellIndex.indexByColumnRow(
          rowIndex: rowIndex, columnIndex: WriteCols.googleFormattedAddress))
      .value = candidate.formattedAddress;
  writeSheet
      .cell(CellIndex.indexByColumnRow(
          rowIndex: rowIndex, columnIndex: WriteCols.googleLatitude))
      .value = candidate.geometry.location.lat;
  writeSheet
      .cell(CellIndex.indexByColumnRow(
          rowIndex: rowIndex, columnIndex: WriteCols.googleLongitude))
      .value = candidate.geometry.location.lng;
}

void main() {
  const textToSearch = 'William\nWilliam description here...\n170.00 cm';
  final lines = textToSearch.split('\n');
  // If your template is always the same,
  // then your number will be at the start of line 3:
  print(lines[2]); // Will print $170.00
  // If you want just your 170 value then this (assuming there is always a decimal):
  final regEx = RegExp(r'\d+');
  final priceValueMatch = regEx.firstMatch(lines[2]);
  final priceInt = int.parse(priceValueMatch.group(0));
  print(priceInt);
}

void googleSearchNearby() {}

// Future<bool> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   //runApp(MyApp());

//   final data = await rootBundle.load('assets/temp.xlsx');
//   final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
//   final wb = Excel.decodeBytes(bytes);

//   final readSheet = wb.sheets[wb.sheets.keys.first];
//   final writeSheet = wb.sheets[wb.sheets.keys.last];

//   // *** Steps before doing any work on a data sheet
//   // *** that's never ran against this code before:
//   // 1. Copy Sheet1 data into Sheet2
//   // 2. Delete all columns after Col "N"
//   // 3. Create new "synced by cols"
//   // 4. Add JSON and URL column
//   // 4. Create new "google" columns

//   // rowIndex starts at 1 vs. 0 to skip the header row
//   for (var rowIndex = 1; rowIndex <= readSheet.rows.length; rowIndex++) {
//     // *** STEP 1 - SEARCH BY PHONE NUMBER ONLY ***
//     final phoneSearchresult =
//         await searchByPhone(writeSheet, readSheet, rowIndex);

//     if (phoneSearchresult == false) {
//       // *** STEP 2 - SEARCH BY NAME, ADDRESS, CITY AND STATE ***
//       final nameAndAddressResult =
//           await searchByNameAndAddress(writeSheet, readSheet, rowIndex);

//       if (nameAndAddressResult == false) {
//         print('name and address NOT FOUND - next search would go here.');
//       }
//     } else {
//       print('search by phone successful');
//     }

//     if (rowIndex >= 262) {
//       break;
//     } // only do 1 iteration for now
//   }

//   await wb.encode().then((value) {
//     File(join(
//         r'C:\Users\jared\source\repos\avtopia\data_sync_desktop\assets\temp.xlsx'))
//       ..createSync(recursive: true)
//       ..writeAsBytesSync(value);
//   });
//}

String googleByPhoneURL({@required String phoneNumber}) {
  final url =
      'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?'
      'input=$phoneNumber&inputtype=phonenumber&fields=$basicGoogleFieldList'
      '&key=$apiKey';

  return url;
}

String googleByNameAndAddressURL({@required String searchString}) {
  final url =
      'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?'
      'input=${searchString.toURLSafeString()}'
      '&key=$apiKey'
      '&inputtype=textquery&fields=$basicGoogleFieldList';

  return url;
}

class WriteCols {
  static const int id = 0;
  static const int accountName = 1;
  static const int dba1 = 2;
  static const int dba2 = 3;
  static const int dba3 = 4;
  static const int shipStreet1 = 5;
  static const int shipStreet2 = 6;
  static const int shipCity = 7;
  static const int shipState = 8;
  static const int shipZip = 9;
  static const int shipCountry = 10;
  static const int phone = 11;
  static const int website = 12;
  static const int syncStatus = 13; // Column N
  static const int googleSyncByPhone = 14;
  static const int googleSyncByAddress = 15;
  static const int googleSyncByNameAndAddress = 16;
  static const int googleSyncByNameOnly = 17;
  static const int googleURL = 18;
  static const int googleJSON = 19;
  static const int googleCompanyName = 20;
  static const int googleBusinessStatus = 21;
  static const int googlePlaceID = 22;
  static const int googleFormattedAddress = 23;
  static const int googleLatitude = 24;
  static const int googleLongitude = 25;
}

class AvtopiaCols {
  static const int id = 0;
  static const int accountName = 1;
  static const int dba1 = 2;
  static const int dba2 = 3;
  static const int dba3 = 4;
  static const int shipStreet1 = 5;
  static const int shipStreet2 = 6;
  static const int shipCity = 7;
  static const int shipState = 8;
  static const int shipZip = 9;
  static const int shipCountry = 10;
  static const int phone = 11;
  static const int website = 12;
  static const int busCat1 = 13;
  static const int busCat2 = 14;
  static const int busCat3 = 15;
  static const int busCat4 = 16;
  static const int busCat5 = 17;
  static const int busCat6 = 18;
  static const int busCat7 = 19;
  static const int busCat8 = 20;
  static const int busCat9 = 21;
  static const int busCat10 = 22;
  static const int tag1 = 23;
  static const int tag2 = 24;
  static const int tag3 = 25;
  static const int tag4 = 26;
  static const int tag5 = 27;
  static const int tag6 = 28;
  static const int tag7 = 29;
  static const int tag8 = 30;
  static const int tag9 = 31;
  static const int tag10 = 32;
  static const int tag11 = 33;
  static const int tag12 = 34;
  static const int tag13 = 35;
  static const int tag14 = 36;
  static const int tag15 = 37;
  static const int tag16 = 38;
  static const int tag17 = 39;
  static const int tag18 = 40;
  static const int tag19 = 41;
  static const int tag20 = 42;
  static const int googleSyncByPhone = 43;
  static const int googleSyncByAddress = 44;
  static const int googleSyncByNameAndAddress = 45;
  static const int googleSyncByNameOnly = 46;
  static const int googleRating = 47;
  static const int googleNumberOfReviews = 48;
  static const int googleWebiste = 49;
  static const int googleCompanyName = 50;
  static const int googleStreet = 51;
  static const int googleStreet2 = 52;
  static const int googleCity = 53;
  static const int googleState = 54;
  static const int googleZip = 55;
  static const int googleCountry = 56;
  static const int googleGPSCoordinates = 57;
  static const int googleImageURL = 58;
  static const int googlePlaceID = 59;
}
