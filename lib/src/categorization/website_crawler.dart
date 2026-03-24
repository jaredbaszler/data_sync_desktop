import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;

class WebsiteCrawler {
  final http.Client _client;
  final Duration timeout;

  WebsiteCrawler({
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client();

  /// Fetches the URL and returns extracted visible text, or null on failure.
  Future<String?> fetchPageText(String url) async {
    try {
      var normalizedUrl = url.trim();
      if (!normalizedUrl.startsWith('http://') &&
          !normalizedUrl.startsWith('https://')) {
        normalizedUrl = 'https://$normalizedUrl';
      }

      final response = await _client
          .get(Uri.parse(normalizedUrl), headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; DataSyncBot/1.0)',
          })
          .timeout(timeout);

      if (response.statusCode != 200) return null;

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('text/html')) return null;

      return _extractText(response.body);
    } catch (_) {
      return null;
    }
  }

  /// Parse HTML into a DOM tree, remove non-visible elements, and extract text.
  String _extractText(String htmlContent) {
    final document = html_parser.parse(htmlContent);

    // Remove script and style elements from the DOM
    document.querySelectorAll('script, style, noscript').forEach((e) => e.remove());

    // Extract visible text from the body (or full document if no body)
    final body = document.body ?? document.documentElement;
    if (body == null) return '';

    var text = body.text;
    // Collapse whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Cap at 10,000 chars
    if (text.length > 10000) text = text.substring(0, 10000);
    return text;
  }

  void close() => _client.close();
}
