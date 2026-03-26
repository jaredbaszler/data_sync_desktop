import 'package:excel/excel.dart';
import 'dart:io';

void main() {
  final file = File(r'assets/db_code lookups/FAA - 145 - Repair Stations.xlsx');
  final bytes = file.readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables.values.first;

  print('Sheet: ${excel.tables.keys.first}');
  print('Rows: ${sheet.rows.length}\n');

  // Check the Data objects for actual cell references
  print('--- ROW 0 (headers) - checking Data properties ---');
  final row0 = sheet.rows[0];
  for (var c = 0; c < row0.length; c++) {
    final cell = row0[c];
    if (cell != null) {
      print('  index=$c  colIndex=${cell.columnIndex}  value="${cell.value}"');
    }
  }

  print('\n--- ROW 1 - checking Data properties ---');
  final row1 = sheet.rows[1];
  for (var c = 0; c < row1.length; c++) {
    final cell = row1[c];
    if (cell != null && cell.value != null) {
      print('  index=$c  colIndex=${cell.columnIndex}  value="${cell.value}"');
    }
  }
}
