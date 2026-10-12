import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/media_item.dart';

class ArchiveException implements Exception {
  const ArchiveException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ArchivePage {
  const ArchivePage(this.items, {required this.hasMore});
  final List<MediaItem> items;
  final bool hasMore;
}

/// Searches the Internet Archive (archive.org) for audio that is public domain
/// or Creative Commons licensed. No API key or account is needed.
class ArchiveApi {
  ArchiveApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const pageSize = 20;

  static String _clean(String query) =>
      query.replaceAll(RegExp(r'[^\w\s\-]', unicode: true), ' ').trim();

  static String _first(Object? value) {
    if (value is List && value.isNotEmpty) return value.first.toString();
    return value?.toString() ?? '';
  }

  static bool _hasCollection(Object? value, String name) => value is List
      ? value.map((e) => e.toString()).contains(name)
      : value?.toString() == name;

  /// Short license label, or null when the item is not clearly free to use.
  static String? licenseLabel(String licenseUrl, {bool librivox = false}) {
    if (librivox) return 'Public domain';
    final url = licenseUrl.toLowerCase();
    if (!url.contains('creativecommons.org')) return null;
    if (url.contains('/publicdomain/zero')) return 'CC0';
    if (url.contains('/publicdomain/')) return 'Public domain';
    final match = RegExp(r'/licenses/([a-z\-]+)/([0-9.]+)').firstMatch(url);
    if (match == null) return 'Creative Commons';
    return 'CC ${match.group(1)!.toUpperCase()} ${match.group(2)}';
  }

  Future<ArchivePage> search(String query, {int page = 1}) async {
    final text = _clean(query);
    if (text.isEmpty) return const ArchivePage([], hasMore: false);
    final q =
        '(title:($text) OR creator:($text)) AND mediatype:audio AND '
        '(licenseurl:[* TO *] OR collection:librivox)';
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': q,
      'fl[]': ['identifier', 'title', 'creator', 'licenseurl', 'collection'],
      'rows': '$pageSize',
      'page': '$page',
      'sort[]': 'downloads desc',
      'output': 'json',
    });
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ArchiveException(
        'Could not reach the Internet Archive. Check your connection.',
      );
    }
    if (response.statusCode != 200) {
      throw ArchiveException(
        'The Internet Archive returned an error (${response.statusCode}).',
      );
    }
    return parse(response.body, page: page);
  }

  static ArchivePage parse(String body, {int page = 1}) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw const ArchiveException('Unexpected response from the Archive.');
    }
    final response = json['response'] as Map<String, dynamic>? ?? {};
    final docs = (response['docs'] as List? ?? []).whereType<Map>();
    final total = (response['numFound'] as num?)?.toInt() ?? 0;
    final items = <MediaItem>[];
    for (final doc in docs) {
      final id = _first(doc['identifier']);
      if (id.isEmpty) continue;
      final label = licenseLabel(
        _first(doc['licenseurl']),
        librivox: _hasCollection(doc['collection'], 'librivox'),
      );
      if (label == null) continue;
      final title = _first(doc['title']);
      items.add(
        MediaItem(
          id: 'archive-$id',
          title: title.isEmpty ? id : title,
          creator: _first(doc['creator']).isEmpty
              ? 'Internet Archive'
              : _first(doc['creator']),
          category: label,
          kind: MediaKind.music,
          source: 'archive:$id',
          color: 0xFFCF9DEB,
          art: id.length % 5,
          description: 'From the Internet Archive. License: $label.',
          artworkUrl: 'https://archive.org/services/img/$id',
        ),
      );
    }
    return ArchivePage(items, hasMore: page * pageSize < total);
  }

  /// Finds a playable MP3 file for an item and returns its direct URL.
  Future<String> resolve(MediaItem item) async {
    if (!item.isArchive) throw const ArchiveException('Not an Archive item.');
    final id = item.source.substring(8);
    final uri = Uri.https('archive.org', '/metadata/$id');
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ArchiveException(
        'Could not reach the Internet Archive. Check your connection.',
      );
    }
    if (response.statusCode != 200) {
      throw const ArchiveException('This item is not available right now.');
    }
    return pickMp3(id, response.body);
  }

  static String pickMp3(String id, String body) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw const ArchiveException('Unexpected response from the Archive.');
    }
    final files = (json['files'] as List? ?? []).whereType<Map>().toList();
    Map? pick;
    for (final f in files) {
      final name = (f['name'] ?? '').toString().toLowerCase();
      if (name.endsWith('.mp3') && f['private'] != 'true') {
        pick = f;
        break;
      }
    }
    if (pick == null) {
      throw const ArchiveException('No playable MP3 found for this item.');
    }
    final segments = ['download', id, ...pick['name'].toString().split('/')];
    return Uri(
      scheme: 'https',
      host: 'archive.org',
      pathSegments: segments,
    ).toString();
  }

  void dispose() => _client.close();
}
