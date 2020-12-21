import 'dart:convert';
import 'dart:io';

import 'package:data_sync_desktop/models/google_candidates.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //runApp(MyApp());

  final data = await rootBundle.load('assets/test_file_2020_11_26_copy.xlsx');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final wb = Excel.decodeBytes(bytes);

  final readSheet = wb.sheets[wb.sheets.keys.first];
  final writeSheet = wb.sheets[wb.sheets.keys.last];
  final temp = 0;

  // Steps before doing any work:
  // 1. Copy Sheet1 data into Sheet2
  // 2. Delete all columns after Col "N"
  // 3. Create new "synced by cols"
  // 4. Add JSON and URL column
  // 4. Create new "google" columns

  var rowIndex = 1; // Skip header row as header row, start with first data row
  for (final row in readSheet.rows) {
    // Transform the phone number
    //final phoneCell = cellByIndex(writeSheet, rowIndex, Cols.phone);
    //final countryCell = cellByIndex(writeSheet, rowIndex, Cols.shipCountry);

    // Copy this row into the new file
    for (var colIndex = 0; colIndex <= AvtopiaCols.website; colIndex++) {
      copyCell(writeSheet, readSheet, rowIndex, colIndex);
    }

    final listOfCandidates = GoogleCandidates.fromJson(
        jsonDecode(await rootBundle.loadString('google_returns/byPhone.json')));

    for (final result in listOfCandidates.candidates) {
      writeSheet
          .cell(CellIndex.indexByColumnRow(
              rowIndex: rowIndex, columnIndex: WriteCols.googleCompanyName))
          .value = result.name;
      writeSheet
          .cell(CellIndex.indexByColumnRow(
              rowIndex: rowIndex, columnIndex: WriteCols.googleBusinessStatus))
          .value = result.businessStatus;
      writeSheet
          .cell(CellIndex.indexByColumnRow(
              rowIndex: rowIndex, columnIndex: WriteCols.googlePlaceID))
          .value = result.placeId;
      writeSheet
          .cell(CellIndex.indexByColumnRow(
              rowIndex: rowIndex,
              columnIndex: WriteCols.googleFormattedAddress))
          .value = result.formattedAddress;
      writeSheet
          .cell(CellIndex.indexByColumnRow(
              rowIndex: rowIndex, columnIndex: WriteCols.googleLatitude))
          .value = result.geometry.location.lat;
      writeSheet
          .cell(CellIndex.indexByColumnRow(
              rowIndex: rowIndex, columnIndex: WriteCols.googleLongitude))
          .value = result.geometry.location.lng;
    }

    // *** STEP 1 - SEARCH BY PHONE NUMBER ONLY ***
    // final byPhoneUrl = googleByPhoneURL(
    //     phoneNumber:
    //         phoneCell.value.toString().toIntlPhoneFormat(countryCell.value));

    // print(url);
    // final response = await http.get(byPhoneUrl);

    // if (response.statusCode == 200) {
    //   final listOfCandidates =
    //       GoogleCandidates.fromJson(jsonDecode(response.body));

    //   final temp = listOfCandidates;
    // } else {
    //   print('Request failed with status: ${response.statusCode}.');
    // }

    rowIndex++;

    if (rowIndex > 5) {
      break;
    } // only do 1 iteration for now
  }

  await wb.encode().then((value) {
    File(join(
        r'C:\Users\jared\source\repos\avtopia\data_sync_desktop\assets\temp.xlsx'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(value);
  });
}

String googleByPhoneURL({@required String phoneNumber}) {
  final url =
      'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?'
      'input=$phoneNumber&inputtype=phonenumber&fields=$basicGoogleFieldList'
      '&key=$apiKey';

  return url;
}

String googleByNameURL({@required String businessName}) {
  final url =
      'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?'
      'input=${businessName.toURLSafeString()}'
      '&api_key=$apiKey'
      '&inputtype=textquery;&fields=$basicGoogleFieldList';

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
  static const int googleJSON = 18;
  static const int googleCompanyName = 19;
  static const int googleBusinessStatus = 20;
  static const int googlePlaceID = 21;
  static const int googleFormattedAddress = 22;
  static const int googleLatitude = 23;
  static const int googleLongitude = 24;
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
