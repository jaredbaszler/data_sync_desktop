import 'package:excel/excel.dart';
import 'dart:io';

void main() async {
  final excelFile = File(
    r'c:\Users\jared\source\repos\data_sync_desktop\assets\db_code lookups\FAR 145 Repair Stations _ ALL USA with Category Codes.xlsx',
  );

  if (!excelFile.existsSync()) {
    print('File not found: ${excelFile.path}');
    return;
  }

  print('Loading Excel file...\n');

  try {
    final bytes = excelFile.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);

    // Get the first sheet
    final sheet = excel.sheets.values.first;
    final table = sheet.rows;

    print('Total rows: ${table.length}');
    print('Total columns: ${table.isNotEmpty ? table.first.length : 0}\n');

    // Print all column headers (first row)
    if (table.isNotEmpty) {
      print('=' * 150);
      print('COLUMN HEADERS (Row 1):');
      print('=' * 150);
      final headers = table.first;
      for (int i = 0; i < headers.length; i++) {
        final col = String.fromCharCode(65 + (i % 26)); // A, B, C...
        final colDouble = i ~/ 26;
        final fullCol = (colDouble > 0 ? String.fromCharCode(64 + colDouble) : '') + col;
        print('[$fullCol] ${i.toString().padLeft(3)}: ${headers[i]?.value ?? ""}');
      }

      print('\n' + '=' * 150);
      print('COLUMN U-Z (Rating columns):');
      print('=' * 150);
      for (int i = 20; i < 26 && i < headers.length; i++) {
        final col = String.fromCharCode(65 + i);
        print('[${col}] ${i.toString().padLeft(3)}: ${headers[i]?.value ?? ""}');
      }

      // Print first 3 data rows
      print('\n' + '=' * 150);
      print('FIRST 3 DATA ROWS:');
      print('=' * 150);

      final dataRows = table.skip(1).take(3).toList();
      for (int rowIdx = 0; rowIdx < dataRows.length; rowIdx++) {
        print('\nRow ${rowIdx + 2}: (Data Row ${rowIdx + 1})');
        print('-' * 150);
        final row = dataRows[rowIdx];
        for (int i = 0; i < row.length; i++) {
          final col = String.fromCharCode(65 + (i % 26));
          final colDouble = i ~/ 26;
          final fullCol = (colDouble > 0 ? String.fromCharCode(64 + colDouble) : '') + col;
          final value = row[i]?.value ?? "";
          print('  [$fullCol] ${i.toString().padLeft(3)}: $value');
        }
      }

      print('\n' + '=' * 150);
      print('DATA ROW SUMMARY (Columns U-Z):');
      print('=' * 150);
      for (int rowIdx = 0; rowIdx < dataRows.length; rowIdx++) {
        print('\nRow ${rowIdx + 2} - Rating Columns (U-Z):');
        final row = dataRows[rowIdx];
        for (int i = 20; i < 26 && i < row.length; i++) {
          final col = String.fromCharCode(65 + i);
          final value = row[i]?.value ?? "";
          print('  [$col]: $value');
        }
      }

      print('\n' + '=' * 150);
      print('SUMMARY:');
      print('=' * 150);
      print('Total Data Rows: ${table.length - 1}');
      print('Total Columns: ${table.first.length}');
    }
  } catch (e) {
    print('Error reading Excel file: $e');
  }
}
