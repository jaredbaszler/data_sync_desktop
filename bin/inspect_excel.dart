import 'dart:io';
import 'package:excel/excel.dart';

void main() async {
  const String filePath =
      r'assets\db_code lookups\FAR 145 _Florida_ALL_Repair Station_ With category codes.xlsx';

  try {
    final file = File(filePath);
    if (!file.existsSync()) {
      print('Error: File not found at $filePath');
      exit(1);
    }

    var bytes = file.readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);

    print('=' * 100);
    print('Available sheets: ${excel.tables.keys.toList()}');
    print('=' * 100);

    var sheet = excel.tables.values.first;

    print('\n' + '=' * 100);
    print(
        'INSPECTING: FAR 145 _Florida_ALL_Repair Station_ With category codes.xlsx');
    print(
        'Sheet: ${excel.tables.keys.first} | Max Rows: ${sheet.maxRows} | Max Cols: ${sheet.maxCols}');
    print('=' * 100);

    // Get all column headers from the first row using .rows
    print('\n1. COLUMN HEADERS (Row 1):');
    print('-' * 100);

    List<String?> headers = [];
    if (sheet.rows.isNotEmpty) {
      var headerRow = sheet.rows[0];
      for (int col = 0; col < headerRow.length; col++) {
        var cell = headerRow[col];
        String? headerValue = cell?.value?.toString();
        headers.add(headerValue);

        String colLetter = getColumnLetter(col);
        if (headerValue != null && headerValue.isNotEmpty) {
          print('${col + 1}. Col $colLetter: $headerValue');
        }
      }
    }

    // Print first 3 data rows with all column values
    print('\n\n2. FIRST 3 DATA ROWS:');
    print('-' * 100);

    int dataRowsShown = 0;
    for (int row = 1; row < sheet.rows.length && dataRowsShown < 3; row++) {
      print('\nRow ${row + 1}:');
      var rowData = sheet.rows[row];
      for (int col = 0; col < rowData.length; col++) {
        var cell = rowData[col];
        String? value = cell?.value?.toString();
        String colLetter = getColumnLetter(col);

        // Truncate long values
        if (value != null && value.length > 50) {
          value = value.substring(0, 50) + '...';
        }

        if (value != null && value.isNotEmpty) {
          print('  $colLetter: $value');
        } else {
          print('  $colLetter: (empty)');
        }
      }
      dataRowsShown++;
    }

    // Count total rows
    int totalRows = sheet.rows.length;
    print('\n\n3. TOTAL ROWS: $totalRows');

    // Check columns U-Z for rating info
    print('\n\n4. COLUMNS U-Z HEADERS (Rating columns):');
    print('-' * 100);

    List<String> ratingColumns = ['U', 'V', 'W', 'X', 'Y', 'Z'];
    for (String colLetter in ratingColumns) {
      int colIndex = getColumnIndex(colLetter);
      if (sheet.rows.isNotEmpty && colIndex < sheet.rows[0].length) {
        var cell = sheet.rows[0][colIndex];
        String? headerValue = cell?.value?.toString();
        print('Column $colLetter: $headerValue');
      } else {
        print('Column $colLetter: (column out of range)');
      }
    }

    print('\n\n5. FIRST 3 DATA VALUES IN COLUMNS U-Z:');
    print('-' * 100);

    dataRowsShown = 0;
    for (int row = 1; row < sheet.rows.length && dataRowsShown < 3; row++) {
      print('\nRow ${row + 1}:');
      var rowData = sheet.rows[row];
      for (String colLetter in ratingColumns) {
        int colIndex = getColumnIndex(colLetter);
        String value = '(empty)';
        if (colIndex < rowData.length) {
          var cell = rowData[colIndex];
          value = cell?.value?.toString() ?? '(empty)';
        }
        print('  $colLetter: $value');
      }
      dataRowsShown++;
    }

    // Summary: Look for rating-related columns
    print('\n\n6. RATING COLUMNS VERIFICATION:');
    print('-' * 100);
    bool hasRatingColumns = false;

    List<String> expectedRatings = [
      'Rating - Airframe',
      'Rating - Instrument',
      'Rating - Limited',
      'Rating - Powerplant',
      'Rating - Propeller',
    ];

    for (String expectedRating in expectedRatings) {
      bool found = headers.any((h) => h?.contains(expectedRating) ?? false);
      if (found) {
        print('✓ Found: $expectedRating');
        hasRatingColumns = true;
      } else {
        print('✗ NOT found: $expectedRating');
      }
    }

    print('\n' + '=' * 100);
    if (hasRatingColumns) {
      print('CONFIRMED: This file contains the rating column structure!');
      print(
          'This is a VALID file for FAR 145 repair station data with rating codes.');
    } else {
      print('WARNING: Rating columns not found in the expected locations!');
    }
    print('=' * 100);
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}

String getColumnLetter(int index) {
  if (index < 26) {
    return String.fromCharCode(65 + index); // A-Z
  } else if (index < 52) {
    return 'A${String.fromCharCode(65 + (index - 26))}'; // AA-AZ
  } else {
    return 'B${String.fromCharCode(65 + (index - 52))}'; // BA-BZ
  }
}

int getColumnIndex(String letter) {
  if (letter.length == 1) {
    return letter.codeUnitAt(0) - 65; // A-Z -> 0-25
  } else if (letter.length == 2) {
    if (letter[0] == 'A') {
      return 26 + (letter[1].codeUnitAt(0) - 65); // AA-AZ -> 26-51
    } else if (letter[0] == 'B') {
      return 52 + (letter[1].codeUnitAt(0) - 65); // BA-BZ -> 52-77
    }
  }
  return 0;
}
