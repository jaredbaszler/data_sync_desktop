class CategoryCode {
  final String code;
  final String description;
  final String operationGroup;
  final String searchTerms; // pipe-delimited search terms

  CategoryCode({
    required this.code,
    required this.description,
    required this.operationGroup,
    required this.searchTerms,
  });

  List<String> get searchTermList =>
      searchTerms.split('|').map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toList();

  @override
  String toString() => 'CategoryCode($code: $description)';
}

class CategoryMatch {
  final String code;
  final String searchTerms;
  final String source; // 'far' or 'search_term'

  CategoryMatch({
    required this.code,
    required this.searchTerms,
    required this.source,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CategoryMatch && code == other.code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'CategoryMatch($code from $source)';
}
