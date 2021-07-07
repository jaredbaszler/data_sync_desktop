import 'dart:convert';
import 'dart:io';

import 'package:data_sync_desktop/models/candidates.dart';
import 'package:data_sync_desktop/models/google_candidates.dart';
import 'package:data_sync_desktop/models/google_nearby.dart';
import 'package:data_sync_desktop/models/place_detail_response.dart';
import 'package:data_sync_desktop/utils/extensions.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';

// belongs to avtopiadev@gmail.com
const apiKey = 'AIzaSyAUoR1hu32epmid_r-h7_AiXQWhNu3zr3U';
const placesSearchBasicList = 'business_status,formatted_address,geometry,'
    'icon,name,permanently_closed,place_id,plus_code,types';
const detailsSearchBasicList =
    'address_component,adr_address,business_status,formatted_address,'
    'geometry,icon,name,permanently_closed,photo,place_id,plus_code,'
    'type,url,utc_offset,vicinity';
const detailsSearchContactList = 'formatted_phone_number,'
    'international_phone_number,opening_hours,website';
const detailsSearchAtmosphereList =
    'price_level,rating,review,user_ratings_total';
const hexRed = '#ff9191';
const hexGreen = '#8bd98c';

Data cellByIndex(Sheet sheet, int rowIndex, int colIndex) {
  Data returnCell;

  for (final cell in sheet.row(rowIndex)) {
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

Future<bool> getPlaceDetails(
    Sheet writeSheet, Sheet readSheet, int rowIndex, String placeID) async {
  final placeDetailsURL = getPlaceDetailsURL(placeID: placeID);
  print('Getting Place Details from: $placeDetailsURL');

  final response = await http.get(Uri.parse(placeDetailsURL));

  PlaceDetailResponse placeDetailResponse;

  if (response.statusCode == 200) {
    placeDetailResponse =
        PlaceDetailResponse.fromJson(jsonDecode(response.body));
    final placeDetails = placeDetailResponse.result;

    if (placeDetails == null) {
      return false;
    }

    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googlePlacesDetailsJSON))
        .value = jsonEncode(placeDetailResponse).toString();
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleAdrAddress))
        .value = placeDetails.adrAddress;
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex,
            columnIndex: WriteCols.googleFormattedPhoneNumber))
        .value = placeDetails.formattedPhoneNumber;
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleIcon))
        .value = placeDetails.icon;
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex,
            columnIndex: WriteCols.googleInternationalPhoneNumber))
        .value = placeDetails.internationalPhoneNumber;
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleRating))
        .value = placeDetails.rating;
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleUTCOffset))
        .value = placeDetails.utcOffset;
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleVicinity))
        .value = placeDetails.vicinity;
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleBusinessURL))
        .value = placeDetails.website;
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleRating))
        .value = placeDetails.rating;
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleNumReviews))
        .value = placeDetails.reviews?.length ?? '';
    // There is also a USER_RATINGS_TOTAL which didn't seem to calculate
    // correctly on the 1 listing I did look on.
    // Also, PRICE_LEVEL also doesn't seem to come through on listings like ours
  } else {
    print('Request failed with status: ${response.statusCode}.');
    return false;
  }

  return true;
}

Future<bool> searchByWebsiteUrl(
    Sheet writeSheet, Sheet readSheet, int rowIndex) async {
  final websiteUrl = cellByIndex(writeSheet, rowIndex, AvtopiaCols.website);

  if (websiteUrl.value == null) {
    return false;
  }

  final searchUrl = googleByTextQueryURL(
      searchString: websiteUrl.value.toString().stripUrl());

  print('rowIndex: $rowIndex / searchUrl: $searchUrl');

  final response = await http.get(Uri.parse(searchUrl));
  GoogleCandidates listOfCandidates;

  if (response.statusCode == 200) {
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleMapsURL))
        .value = searchUrl;

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
            rowIndex: rowIndex, columnIndex: WriteCols.googleSyncByWebsite))
        .value = validMatch ? 'X' : '';

    if (validMatch) {
      writeGoogleCanidateInfo(candidate, writeSheet, readSheet, rowIndex);
    }
  }

  return true;
}

Future<bool> searchByNameAndAddress(
    Sheet writeSheet, Sheet readSheet, int rowIndex) async {
  final companyNameCell =
      cellByIndex(writeSheet, rowIndex, AvtopiaCols.accountName);
  final dba1Cell = cellByIndex(writeSheet, rowIndex, AvtopiaCols.dba1);
  final dba2Cell = cellByIndex(writeSheet, rowIndex, AvtopiaCols.dba2);
  final dba3Cell = cellByIndex(writeSheet, rowIndex, AvtopiaCols.dba3);
  final shipStreet1Cell =
      cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipStreet1);
  final shipStreet2Cell =
      cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipStreet2);
  final shipCityCell = cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipCity);
  final shipStateCell =
      cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipState);
  final shipZipCell = cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipZip);

  if (shipStateCell.value.toString().trim().isEmpty) {
    return false;
  }

  final searchString = '${companyNameCell.value ?? ''} '
      '${dba1Cell?.value ?? ''} ${dba2Cell?.value ?? ''} '
      '${dba3Cell?.value ?? ''} '
      '${shipStreet1Cell.value ?? ''} ${shipStreet2Cell.value ?? ''} '
      '${shipCityCell.value ?? ''} ${shipStateCell.value ?? ''} '
      '${shipZipCell.value ?? ''}';

  final searchUrl = googleByTextQueryURL(searchString: searchString);

  final response = await http.get(Uri.parse(searchUrl));
  GoogleCandidates listOfCandidates;

  print('Searching name and address ($searchString} at URL:$searchUrl');

  if (response.statusCode == 200) {
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleMapsURL))
        .value = searchUrl;

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
      // Sometimes the types of listing comes back "premise"
      validMatch = false;
      writeSheet
          .cell(CellIndex.indexByColumnRow(
              rowIndex: rowIndex, columnIndex: WriteCols.googleListingTypes))
          .value = candidate.types.join(',');
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

    if (validMatch) {
      writeGoogleCanidateInfo(candidate, writeSheet, readSheet, rowIndex);
    }
  }

  return true;
}

Future<GoogleNearbyResult> searchNearby(
    Sheet readSheet, int rowIndex, String nextPageToken) async {
  final airpotCodeCell =
      cellByIndex(readSheet, rowIndex, AirportListCols.airportCode);
  final airportLatCell =
      cellByIndex(readSheet, rowIndex, AirportListCols.latitudeDecimalDegrees);
  final airportLongCell =
      cellByIndex(readSheet, rowIndex, AirportListCols.longitudeDecimalDegrees);
  // parameter must be in meters.  8000 = 5 miles, 16000, 10 miles
  const radius = 16000;
  var nearbyResults = GoogleNearbyResult();

  if (airpotCodeCell.value == null ||
      airportLatCell.value == null ||
      airportLongCell.value == null) {
    return nearbyResults;
  }

  final nearbyURL = googleByNearbyURL(
      airportLat: airportLatCell.value,
      airportLong: airportLongCell.value,
      radius: radius,
      nextPageToken: nextPageToken);

  print(nearbyURL);

  try {
    final response = await http.get(Uri.parse(nearbyURL));
    if (response.statusCode == 200) {
      nearbyResults = GoogleNearbyResult.fromJson(jsonDecode(response.body));
    } else {
      print('Request failed with status: ${response.statusCode}.');
    }
  } on Exception catch (err, st) {
    print('HTTP Get Errored: $err / Stack Trace: $st');
  }

  return nearbyResults;
}

Future<bool> searchByPhone(
    Sheet writeSheet, Sheet readSheet, int rowIndex) async {
  // Transform the phone number
  final phoneCell = cellByIndex(writeSheet, rowIndex, AvtopiaCols.phone);
  final countryCell =
      cellByIndex(writeSheet, rowIndex, AvtopiaCols.shipCountry);

  if (phoneCell.value == null || countryCell.value == null) {
    return false;
  }

  final byPhoneUrl = googleByPhoneURL(
      phoneNumber:
          phoneCell.value.toString().toIntlPhoneFormat(countryCell.value));

  print('Searching phone number ${phoneCell.value} at URL:$byPhoneUrl');

  final response = await http.get(Uri.parse(byPhoneUrl));
  GoogleCandidates listOfCandidates;

  if (response.statusCode == 200) {
    writeSheet
        .cell(CellIndex.indexByColumnRow(
            rowIndex: rowIndex, columnIndex: WriteCols.googleMapsURL))
        .value = byPhoneUrl;

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

    writeGoogleCanidateInfo(candidate, writeSheet, readSheet, rowIndex);
  }

  return true;
}

void writeGoogleCanidateInfo(
    Candidates candidate, Sheet writeSheet, Sheet readSheet, int rowIndex) {
  writeSheet
      .cell(CellIndex.indexByColumnRow(
          rowIndex: rowIndex, columnIndex: WriteCols.googleListingTypes))
      .value = candidate.types.join(',');
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

Future<bool> googleSearchNearby() async {
  WidgetsFlutterBinding.ensureInitialized();

  final data =
      await rootBundle.load('assets/Partner Launch - Airport List.xlsx');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final wb = Excel.decodeBytes(bytes);

  final readSheet =
      wb.sheets[wb.sheets.keys.firstWhere((a) => a == 'Partner Launch')];
  final writeSheet =
      wb.sheets[wb.sheets.keys.firstWhere((a) => a == 'NearbyResults')];

  var writeIndex = 1;
  String nextPageToken;

  // Loop through the designated airports in the Partner Launch tab
  for (var readIndex = 1; readIndex <= readSheet.rows.length; readIndex++) {
    var resultPageNum = 1;
    if (readIndex >= 2) {
      break;
    }

    // Max 60 results which is 3 x 20 results so 3 runs -
    // make another request with the nextPageToken to get the next 20
    while (resultPageNum >= 1 && resultPageNum <= 3) {
      final nearbyResults =
          await searchNearby(readSheet, readIndex, nextPageToken);

      print(
          'nearbyResults count: ${nearbyResults.results.length}, resultPageNum=$resultPageNum');

      for (final nearbyResult in nearbyResults.results) {
        print('writing: ${nearbyResult.name}');
        // Company Name
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex, columnIndex: WriteCols.accountName))
            .value = nearbyResult.name;

        // "Vincinity - using the street address to display for now"
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex, columnIndex: WriteCols.shipStreet1))
            .value = nearbyResult.vicinity;

        // Airport Code - copied from "July 1 Launch" which is the read sheet
        writeSheet
                .cell(CellIndex.indexByColumnRow(
                    rowIndex: writeIndex, columnIndex: WriteCols.airportCode))
                .value =
            cellByIndex(readSheet, readIndex, AirportListCols.airportCode)
                .value;

        // Business Status
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex,
                columnIndex: WriteCols.googleBusinessStatus))
            .value = nearbyResult.businessStatus;

        // Latitude
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex, columnIndex: WriteCols.googleLatitude))
            .value = nearbyResult.geometry.location.lat;

        // Longitude
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex, columnIndex: WriteCols.googleLongitude))
            .value = nearbyResult.geometry.location.lng;

        // Longitude
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex, columnIndex: WriteCols.googleLongitude))
            .value = nearbyResult.geometry.location.lng;

        // PlaceID
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex, columnIndex: WriteCols.googlePlaceID))
            .value = nearbyResult.placeId;

        // PlusCode (Global Code)
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex, columnIndex: WriteCols.googleGlobalCode))
            .value = nearbyResult.plusCode?.globalCode;

        // PlusCode (Compound Code)
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex,
                columnIndex: WriteCols.googleCompoundCode))
            .value = nearbyResult.plusCode?.compoundCode;

        // Google Overall Rating
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex, columnIndex: WriteCols.googleRating))
            .value = nearbyResult.rating;

        // Business Types
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex,
                columnIndex: WriteCols.googleListingTypes))
            .value = nearbyResult.types.join(',');

        // Num Reviews
        writeSheet
            .cell(CellIndex.indexByColumnRow(
                rowIndex: writeIndex, columnIndex: WriteCols.googleNumReviews))
            .value = nearbyResult.userRatingsTotal;

        writeIndex++;
      }

      nextPageToken = nearbyResults.nextPageToken == ''
          ? null
          : nearbyResults.nextPageToken;

      if (nextPageToken == null) {
        // break out of next-page while loop as this means no more pages exist
        break;
      } else {
        // Need a short delay to let the page token process
        await Future.delayed(const Duration(milliseconds: 2000));
      }
      resultPageNum++;
    }
  }

  await wb.encode().then((value) {
    File(join(
        r'C:\Users\jared\source\repos\avtopia\data_sync_desktop\assets\Partner Launch - Airport List.xlsx'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(value);
  });

  return true;
}

Future<bool> getGooglePlacesData() async {
  WidgetsFlutterBinding.ensureInitialized();

  final data = await rootBundle.load('assets/temp.xlsx');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final wb = Excel.decodeBytes(bytes);

  final readSheet =
      wb.sheets[wb.sheets.keys.firstWhere((a) => a == 'BetaData')];
  final writeSheet =
      wb.sheets[wb.sheets.keys.firstWhere((a) => a == 'BetaDataResults')];

  // *** Steps before doing any work on a data sheet
  // *** that's never ran against this code before:
  // 1. Copy Sheet1 data into Sheet2
  // 2. Delete all columns after Col "N"
  // 3. Create new "synced by cols"
  // 4. Add JSON and URL column
  // 4. Create new "google" columns
  // 5. Change any states that are spelled out to correct abbreviation

  // rowIndex starts at 2 vs. 0 to skip the header row
  for (var rowIndex = 1; rowIndex <= readSheet.rows.length; rowIndex++) {
    if (rowIndex >= 25) {
      // 496) {
      break;
    }

    const queryAPI = false;

    if (queryAPI) {
      var anySuccess = false;

      // *** STEP 1 - SEARCH BY PHONE NUMBER ONLY ***
      final phoneSearchresult =
          await searchByPhone(writeSheet, readSheet, rowIndex);

      if (phoneSearchresult == false) {
        // *** STEP 2 - SEARCH BY NAME, ADDRESS, CITY AND STATE ***
        final nameAndAddressResult =
            await searchByNameAndAddress(writeSheet, readSheet, rowIndex);

        if (nameAndAddressResult == false) {
          // *** STEP 3 - SEARCH BY URL ONLY
          final urlSearchResult =
              await searchByWebsiteUrl(writeSheet, readSheet, rowIndex);

          if (urlSearchResult == false) {
            // **** STEP 4 - next search here *****

          } else {
            print('search by URL successful');
            anySuccess = true;
          }
        } else {
          print('search by name and address successful');
          anySuccess = true;
        }
      } else {
        anySuccess = true;
        print('search by phone successful');
      }

      // TODO: turn this on if we want to pull in place details which cost more
      if (anySuccess) {
        //   // Go get the details for this line
        //   final placeID = writeSheet
        //       .cell(CellIndex.indexByColumnRow(
        //           rowIndex: rowIndex, columnIndex: WriteCols.googlePlaceID))
        //       .value
        //       ?.toString();

        //   if (placeID != null) {
        //     await getPlaceDetails(writeSheet, readSheet, rowIndex, placeID);
        //   }
      }
    }

    final syncStatusCell =
        cellByIndex(writeSheet, rowIndex, WriteCols.syncStatus);
    final syncStatusCellValue = syncStatusCell.value.toString().toLowerCase();

    syncStatusCell.cellStyle = CellStyle(
        backgroundColorHex: syncStatusCellValue == 'yes' ? hexGreen : hexRed);

    // *** COMPARATIVE ANALYSIS BETWEEN OUR DATA AND GOOGLE DATA
    if (syncStatusCellValue == 'yes' && queryAPI == false) {
      compareToGoogleData(writeSheet, rowIndex);
    }
  }

  await wb.encode().then((value) {
    File(join(
        r'C:\Users\jared\source\repos\avtopia\data_sync_desktop\assets\temp.xlsx'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(value);
  });

  return true;
}

Future<bool> main() async {
  print('main running');
  return googleSearchNearby();
}

void compareToGoogleData(Sheet writeSheet, int rowIndex) {
  // * compare comapny names
  final avCompNameCell =
      cellByIndex(writeSheet, rowIndex, WriteCols.accountName);
  final avDba1Cell = cellByIndex(writeSheet, rowIndex, WriteCols.dba1);
  final avDba2Cell = cellByIndex(writeSheet, rowIndex, WriteCols.dba2);
  final avDba3Cell = cellByIndex(writeSheet, rowIndex, WriteCols.dba3);
  final googleCompNameCell =
      cellByIndex(writeSheet, rowIndex, WriteCols.googleCompanyName);

  var numberOfMatches = 0;

  if (findStringMatches(
      avCompNameCell.value.toString(), googleCompNameCell.value.toString())) {
    numberOfMatches++;
  }

  if (findStringMatches(
      avDba1Cell.value.toString(), googleCompNameCell.value.toString())) {
    numberOfMatches++;
  }

  if (findStringMatches(
      avDba2Cell.value.toString(), googleCompNameCell.value.toString())) {
    numberOfMatches++;
  }

  if (findStringMatches(
      avDba3Cell.value.toString(), googleCompNameCell.value.toString())) {
    numberOfMatches++;
  }

  googleCompNameCell.cellStyle =
      CellStyle(backgroundColorHex: numberOfMatches == 0 ? hexRed : hexGreen);

  // * Compare addresses
  final avStreet1 = cellByIndex(writeSheet, rowIndex, WriteCols.shipStreet1);
  final avStreet2 = cellByIndex(writeSheet, rowIndex, WriteCols.shipStreet2);
  final avCity = cellByIndex(writeSheet, rowIndex, WriteCols.shipCity);
  final avState = cellByIndex(writeSheet, rowIndex, WriteCols.shipState);
  final avZip = cellByIndex(writeSheet, rowIndex, WriteCols.shipZip);
  final googleAddress =
      cellByIndex(writeSheet, rowIndex, WriteCols.googleFormattedAddress);
  final matchStreet = cellByIndex(writeSheet, rowIndex, WriteCols.matchStreet);
  final matchCity = cellByIndex(writeSheet, rowIndex, WriteCols.matchCity);
  final matchState = cellByIndex(writeSheet, rowIndex, WriteCols.matchState);
  final matchZip = cellByIndex(writeSheet, rowIndex, WriteCols.matchZip);

  final googleAddressSplit = googleAddress.value.toString().split(',');
  final avStreet1Expanded =
      avStreet1.value.toString().trim().toLowerCase().toExpandAbbreviations();
  final avStreet2Expanded =
      avStreet2.value.toString().trim().toLowerCase().toExpandAbbreviations();

  for (final googleAddressPart in googleAddressSplit) {
    if (avStreet1.value.toString().trim().isEmpty) {
      break;
    }

    final googleAddressPartExpanded =
        googleAddressPart.trim().toLowerCase().toExpandAbbreviations();

    if (googleAddressPartExpanded.contains(avStreet1Expanded) ||
        avStreet1Expanded.contains(googleAddressPartExpanded)) {
      matchStreet.value = 'X';
      break;
    }

    if (avStreet2.value.toString().trim().isEmpty) {
      break;
    }

    if (googleAddressPartExpanded.contains(avStreet2Expanded) ||
        avStreet2Expanded.contains(googleAddressPartExpanded)) {
      matchStreet.value = 'X';
      break;
    } else {
      matchStreet.value = ' ';
    }
  }

  matchStreet.cellStyle = CellStyle(
      backgroundColorHex: matchStreet.value == 'X' ? hexGreen : hexRed);

  if (avCity.value.toString().isNotEmpty &&
      googleAddress.value
          .toString()
          .toLowerCase()
          .contains(avCity.value.toString().toLowerCase())) {
    matchCity.value = 'X';
  } else {
    matchCity.value = ' ';
  }

  matchCity.cellStyle =
      CellStyle(backgroundColorHex: matchCity.value == 'X' ? hexGreen : hexRed);

  if (avState.value.toString().isNotEmpty &&
      googleAddress.value.toString().contains(
          avState.value.toString().toStateAbbreviation().toUpperCase())) {
    matchState.value = 'X';
  } else {
    matchState.value = ' ';
  }

  matchState.cellStyle = CellStyle(
      backgroundColorHex: matchState.value == 'X' ? hexGreen : hexRed);

  if (avZip.value.toString().isNotEmpty) {
    var zipString = avZip.value.toString();
    if (zipString.contains('-')) {
      zipString = zipString.substring(0, zipString.indexOf('-'));
    }
    if (googleAddress.value.toString().toLowerCase().contains(zipString)) {
      matchZip.value = 'X';
    } else {
      matchZip.value = ' ';
    }
  }

  matchZip.cellStyle =
      CellStyle(backgroundColorHex: matchZip.value == 'X' ? hexGreen : hexRed);
}

bool findStringMatches(String firstString, String secondString) {
  if (firstString.isEmpty || secondString.isEmpty) {
    return false;
  }

  for (var firstStringWord in firstString.split(' ')) {
    for (var secondStringWord in secondString.split(' ')) {
      firstStringWord = firstStringWord.toLowerCase();
      secondStringWord = secondStringWord.toLowerCase();

      if (firstStringWord == secondStringWord ||
          firstStringWord.contains(secondStringWord) ||
          secondStringWord.contains(firstStringWord)) {
        return true;
      }
    }
  }

  return false;
}

String removeCompanyNameWords(String stringToRemove) {
  var returnValue = stringToRemove;

  returnValue = stringToRemove.replaceAll('llc', '');
  returnValue = returnValue.replaceAll('inc.', '');
  returnValue = returnValue.replaceAll('inc', '');
  returnValue = returnValue.replaceAll(',', '');
  returnValue = returnValue.replaceAll('.', '');

  return returnValue;
}

// Future<bool> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   //runApp(MyApp());

//   final data = await rootBundle.load('assets/temp.xlsx');
//   final bytes = data.buffer.asUint8List(data.offsetInBytes,
// data.lengthInBytes);
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

String googleByNearbyURL(
    {@required double airportLat,
    @required double airportLong,
    @required int radius,
    String nextPageToken}) {
  var url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
      'location=$airportLat,$airportLong&radius=$radius&keyword=aviation&'
      'key=$apiKey';

  if (nextPageToken != null) {
    url += '&pagetoken=$nextPageToken';
  }

  return url;
}

String googleByPhoneURL({@required String phoneNumber}) {
  final url =
      'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?'
      'input=$phoneNumber&inputtype=phonenumber&fields=$placesSearchBasicList'
      '&key=$apiKey';

  return url;
}

String googleByTextQueryURL({@required String searchString}) {
  final url =
      'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?'
      'input=${searchString.toURLSafeString()}'
      '&key=$apiKey'
      '&inputtype=textquery&fields=$placesSearchBasicList';

  return url;
}

String getPlaceDetailsURL({@required String placeID}) {
  final url = 'https://maps.googleapis.com/maps/api/place/details/json?'
      'place_id=$placeID&fields=$detailsSearchBasicList,'
      '$detailsSearchContactList,$detailsSearchAtmosphereList&key=$apiKey';

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
  static const int airportCode = 13;
  static const int busCat1 = 14;
  static const int busCat2 = 15;
  static const int busCat3 = 16;
  static const int busCat4 = 17;
  static const int busCat5 = 18;
  static const int syncStatus = 19;
  static const int googleSyncByPhone = 20;
  static const int googleSyncByNameAndAddress = 21;
  static const int googleSyncByWebsite = 22;
  static const int googleSyncByNameOnly = 23;
  static const int googleMapsURL = 24;
  static const int googleJSON = 25;
  static const int googleCompanyName = 26;
  static const int googleBusinessStatus = 27;
  static const int googlePlaceID = 28;
  static const int googleFormattedAddress = 29;
  static const int matchStreet = 30;
  static const int matchCity = 31;
  static const int matchState = 32;
  static const int matchZip = 33;
  static const int googleLatitude = 34;
  static const int googleLongitude = 35;
  static const int googlePlacesDetailsJSON = 36;
  static const int googleAdrAddress = 37;
  static const int googleFormattedPhoneNumber = 38;
  static const int googleIcon = 39;
  static const int googleID = 40;
  static const int googleInternationalPhoneNumber = 41;
  static const int googleListingTypes = 42;
  static const int googleUTCOffset = 43;
  static const int googleVicinity = 44;
  static const int googleBusinessURL = 45;
  static const int googleRating = 46;
  static const int googleNumReviews = 47;
  static const int googlePriceLevel = 48;
  static const int googleGlobalCode = 49;
  static const int googleCompoundCode = 50;
  static const int googleOpeningHours = 51;
}

class AirportListCols {
  static const int airportName = 0;
  static const int airportCode = 1;
  static const int airportState = 2;
  static const int latitudeDecimalDegrees = 3;
  static const int longitudeDecimalDegrees = 4;
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
  static const int googleSyncByNameAndAddress = 44;
  static const int googleSyncByWebsite = 45;
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
