import 'dart:io';

import 'package:excel/excel.dart';

import '../models/category_code.dart';

class CategoryService {
  final List<CategoryCode> _codes = [];

  List<CategoryCode> get codes => List.unmodifiable(_codes);

  /// Load the category dictionary from the Business Category and Search Excel file.
  /// Expected columns: code, description, operationGroup, searchTerms (pipe-delimited)
  Future<void> loadCategoryDictionary(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('Category dictionary not found', filePath);
    }

    final bytes = file.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);

    // Use the first sheet
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;

    // Find column indices from header row
    final headerRow = sheet.rows.first;
    int? codeCol, descCol, groupCol, searchCol;

    for (var i = 0; i < headerRow.length; i++) {
      final header = headerRow[i]?.value?.toString().toLowerCase().trim() ?? '';
      if (header.contains('code') && !header.contains('search')) {
        codeCol ??= i;
      } else if (header.contains('description') || header.contains('desc')) {
        descCol ??= i;
      } else if (header.contains('group') || header.contains('operation')) {
        groupCol ??= i;
      } else if (header.contains('search')) {
        searchCol ??= i;
      }
    }

    // Fallback: assume columns in order if headers not detected
    codeCol ??= 0;
    descCol ??= 1;
    groupCol ??= 2;
    searchCol ??= 3;

    _codes.clear();

    // Skip header row
    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final code = _cellValue(row, codeCol);
      if (code.isEmpty) continue;

      _codes.add(CategoryCode(
        code: code,
        description: _cellValue(row, descCol),
        operationGroup: _cellValue(row, groupCol),
        searchTerms: _cellValue(row, searchCol),
      ));
    }

    print('Loaded ${_codes.length} category codes from $filePath');
  }

  /// Categorize a business by matching its name and Google types against
  /// the search terms in the category dictionary.
  List<CategoryMatch> categorizeBySearchTerms(String businessName, List<String> googleTypes) {
    final matches = <CategoryMatch>{};
    final lowerName = businessName.toLowerCase();
    final lowerTypes = googleTypes.map((t) => t.toLowerCase()).toList();

    for (final category in _codes) {
      for (final term in category.searchTermList) {
        if (term.isEmpty) continue;

        // Check if the term appears in the business name
        if (lowerName.contains(term)) {
          matches.add(CategoryMatch(
            code: category.code,
            searchTerms: category.searchTerms,
            source: 'search_term',
          ));
          break; // One match per category is enough
        }

        // Check if the term appears in any Google type
        for (final type in lowerTypes) {
          if (type.contains(term) || term.contains(type)) {
            matches.add(CategoryMatch(
              code: category.code,
              searchTerms: category.searchTerms,
              source: 'search_term',
            ));
            break;
          }
        }
      }
    }

    return matches.toList();
  }

  /// Categorize by scanning extracted website text against category search terms.
  List<CategoryMatch> categorizeByWebsiteContent(String websiteText) {
    final matches = <CategoryMatch>{};
    final lowerText = websiteText.toLowerCase();

    for (final category in _codes) {
      for (final term in category.searchTermList) {
        if (term.isEmpty) continue;
        if (lowerText.contains(term)) {
          matches.add(CategoryMatch(
            code: category.code,
            searchTerms: category.searchTerms,
            source: 'website',
          ));
          break;
        }
      }
    }

    return matches.toList();
  }

  /// Look up a category code by its code string
  CategoryCode? getByCode(String code) {
    try {
      return _codes.firstWhere((c) => c.code == code);
    } catch (_) {
      return null;
    }
  }

  String _cellValue(List<Data?> row, int? col) {
    if (col == null || col >= row.length) return '';
    final cell = row[col];
    if (cell == null || cell.value == null) return '';
    final val = cell.value.toString().trim();
    return (val == 'null' || val == 'NaN') ? '' : val;
  }
}
