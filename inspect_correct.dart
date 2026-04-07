import 'package:excel/excel.dart';
import 'dart:io';

void main() async {
  final excelFile = File(
    r'c:\Users\jared\source\repos\data_sync_desktop\assets\db_code lookups\FAA - 145 - Repair Stations.xlsx',
  );

  try {
    final bytes = excelFile.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.sheets.values.first;
    final table = sheet.rows;

    if (table.isEmpty) {
      print('No rows found');
      return;
    }

    // Get headers from row 1
    final headers = table[0];
    print('HEADERS (Row 1):');
    print('=' * 200);
    for (int i = 0; i < headers.length; i++) {
      final col = _colName(i);
      final header = (headers[i]?.value ?? '').toString().trim();
      if (header.isNotEmpty) {
        print('[$col $i]: $header');
      }
    }

    print('\n\nFIRST 3 DATA ROWS:');
    print('=' * 200);
    for (int rowIdx = 1; rowIdx <= 3 && rowIdx < table.length; rowIdx++) {
      print('\nRow ${rowIdx + 1}:');
      final row = table[rowIdx];
      for (int i = 0; i < headers.length; i++) {
        final header = (headers[i]?.value ?? '').toString().trim();
        if (header.isNotEmpty) {
          final val = (row[i]?.value ?? '').toString().trim();
          print('  $header: $val');
        }
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}

String _colName(int index) {
  if (index < 26) return String.fromCharCode(65 + index);
  return String.fromCharCode(64 + (index ~/ 26)) + String.fromCharCode(65 + (index % 26));
}
