import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;
import '../models/media_item.dart';

class CatalogException implements Exception {
  const CatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

Uri httpsAddress(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const CatalogException('Enter a complete HTTPS address.');
  }
  return uri;
}

Future<http.StreamedResponse> openAudioRequest(
  http.Client client,
  Uri uri,
) async {
  for (var hop = 0; hop < 6; hop++) {
    httpsAddress(uri.toString());
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers['User-Agent'] = 'Raaga/2.0';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 25));
    if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
      final location = response.headers['location'];
      await response.stream.listen((_) {}).cancel();
      if (location == null)
        throw const CatalogException(
          'The server returned an invalid redirect.',
        );
      uri = uri.resolve(location);
      continue;
    }
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw CatalogException(
        'The server could not load this content (${response.statusCode}).',
      );
    }
    return response;
  }
  throw const CatalogException('The server redirected too many times.');
}

class FeedResult {
  const FeedResult(this.feed, this.episodes);
  final PodcastFeed feed;
  final List<MediaItem> episodes;
}

class PodcastApi {
  PodcastApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  Future<String> _text(Uri uri) async {
    final response = await openAudioRequest(_client, uri);
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 25),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 5 * 1024 * 1024)
        throw const CatalogException('This feed is too large to load.');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<List<PodcastFeed>> search(String term) async {
    if (term.trim().isEmpty) return [];
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term.trim(),
      'media': 'podcast',
      'entity': 'podcast',
      'limit': '25',
      'country': 'IN',
    });
    final data = jsonDecode(await _text(uri)) as Map<String, dynamic>;
    return (data['results'] as List? ?? [])
        .whereType<Map>()
        .where((r) => (r['feedUrl'] as String? ?? '').startsWith('https://'))
        .map(
          (r) => PodcastFeed(
            url: r['feedUrl'] as String,
            title: r['collectionName'] as String? ?? 'Podcast',
            creator: r['artistName'] as String? ?? 'Podcast',
            artworkUrl: r['artworkUrl600'] as String?,
          ),
        )
        .toList();
  }

  Future<FeedResult> fetchFeed(String address) async {
    final uri = httpsAddress(address);
    return parseFeed(await _text(uri), uri.toString());
  }

  static FeedResult parseFeed(String xml, String address) {
    final document = XmlDocument.parse(xml);
    final channel = document.findAllElements('channel').firstOrNull;
    if (channel == null)
      throw const CatalogException('This address is not a podcast RSS feed.');
    String text(XmlElement e, String name) =>
        e.childElements
            .where((n) => n.name.local == name)
            .firstOrNull
            ?.innerText
            .trim() ??
        '';
    String clean(String s) => s
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    String? image(XmlElement e) {
      for (final node in e.childElements.where(
        (n) => n.name.local == 'image',
      )) {
        final url = node.getAttribute('href') ?? text(node, 'url');
        if (url.startsWith('https://')) return url;
      }
      return null;
    }

    int? duration(String value) {
      if (value.isEmpty) return null;
      var seconds = 0;
      for (final part in value.split(':')) {
        final n = int.tryParse(part);
        if (n == null || n < 0) return null;
        seconds = seconds * 60 + n;
      }
      return seconds * 1000;
    }

    final feed = PodcastFeed(
      url: address,
      title: clean(text(channel, 'title')),
      creator: clean(text(channel, 'author')),
      artworkUrl: image(channel),
    );
    final episodes = <MediaItem>[];
    final seen = <String>{};
    for (final node in channel.findElements('item').take(150)) {
      final enclosures = node.childElements.where(
        (n) => n.name.local == 'enclosure',
      );
      final enclosure = enclosures
          .where(
            (e) =>
                (e.getAttribute('url') ?? '').startsWith('https://') &&
                ((e.getAttribute('type') ?? '').startsWith('audio/') ||
                    (e.getAttribute('type') ?? '').isEmpty),
          )
          .firstOrNull;
      final url = enclosure?.getAttribute('url');
      if (url == null) continue;
      final guid = text(node, 'guid');
      final id =
          'rss-${sha256.convert(utf8.encode('$address|${guid.isEmpty ? url : guid}'))}';
      if (!seen.add(id)) continue;
      episodes.add(
        MediaItem(
          id: id,
          title: clean(text(node, 'title')),
          creator: feed.title,
          category: 'Podcasts',
          kind: MediaKind.podcast,
          source: url,
          color: 0xFFB8ABF5,
          art: episodes.length % 5,
          description: clean(text(node, 'description')),
          feedUrl: address,
          artworkUrl: image(node) ?? feed.artworkUrl,
          durationMs: duration(text(node, 'duration')),
        ),
      );
    }
    if (episodes.isEmpty)
      throw const CatalogException(
        'No playable HTTPS audio episodes were found in this feed.',
      );
    return FeedResult(feed, episodes);
  }

  void dispose() => _client.close();
}
