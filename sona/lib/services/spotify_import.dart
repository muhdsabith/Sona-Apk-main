import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/media_item.dart';
import 'apis.dart';

class SpotifyPlaylistImport {
  const SpotifyPlaylistImport({
    required this.id,
    required this.name,
    required this.owner,
    required this.sourceUrl,
    required this.items,
  });

  final String id;
  final String name;
  final String owner;
  final String sourceUrl;
  final List<MediaItem> items;
}

class SpotifyImportService {
  SpotifyImportService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, String?> _previewCache = {};

  static final RegExp _playlistId = RegExp(r'^[A-Za-z0-9]{22}$');
  static final RegExp _playlistUrl = RegExp(
    r'https?://open\.spotify\.com/(?:embed/)?playlist/([A-Za-z0-9]{22})(?:\?[^\s]*)?',
    caseSensitive: false,
  );
  static final RegExp _playlistUri = RegExp(
    r'spotify:playlist:([A-Za-z0-9]{22})',
    caseSensitive: false,
  );

  static String? findPlaylistReference(String text) {
    final trimmed = text.trim();
    final url = _playlistUrl.firstMatch(trimmed);
    if (url != null) return url.group(0);
    final uri = _playlistUri.firstMatch(trimmed);
    if (uri != null) return uri.group(0);
    if (_playlistId.hasMatch(trimmed)) return trimmed;
    return null;
  }

  static String playlistIdFrom(String value) {
    final trimmed = value.trim();
    final url = _playlistUrl.firstMatch(trimmed);
    if (url != null) return url.group(1)!;
    final uri = _playlistUri.firstMatch(trimmed);
    if (uri != null) return uri.group(1)!;
    if (_playlistId.hasMatch(trimmed)) return trimmed;
    throw const CatalogException('Paste a valid Spotify playlist link.');
  }

  Future<SpotifyPlaylistImport> fetchPlaylist(String value) async {
    final id = playlistIdFrom(value);
    final uri = Uri.parse('https://open.spotify.com/embed/playlist/$id');
    final response = await _client
        .get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml',
          },
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw CatalogException(
        'Spotify could not load this playlist (${response.statusCode}).',
      );
    }
    return parseEmbedHtml(response.body, id);
  }

  static SpotifyPlaylistImport parseEmbedHtml(String html, String id) {
    final match = RegExp(
      r"""<script[^>]*id=["']__NEXT_DATA__["'][^>]*>(.*?)</script>""",
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (match == null) {
      throw const CatalogException(
        'Spotify changed its public playlist page, so Raaga could not read it.',
      );
    }

    dynamic data;
    try {
      data = jsonDecode(match.group(1)!.trim());
    } catch (_) {
      throw const CatalogException('Spotify returned unreadable playlist data.');
    }

    final entity = _findTrackEntity(data);
    if (entity == null) {
      throw const CatalogException(
        'No track list was found in this Spotify playlist.',
      );
    }

    final name = _clean(entity['name']) ?? 'Spotify playlist';
    final owner = _clean(entity['subtitle']) ?? 'Spotify';
    final rows = entity['trackList'] as List;
    final items = <MediaItem>[];
    final seen = <String>{};

    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = raw.map((key, value) => MapEntry(key.toString(), value));
      final title = _clean(row['title']);
      final spotifyUri = _clean(row['uri']);
      if (title == null || spotifyUri == null) continue;
      final trackMatch = RegExp(
        r'^spotify:track:([A-Za-z0-9]{22})$',
      ).firstMatch(spotifyUri);
      if (trackMatch == null) continue;
      final trackId = trackMatch.group(1)!;
      if (!seen.add(trackId)) continue;
      final artist = _clean(row['subtitle']) ?? 'Spotify';
      final preview = _httpsUrl(row['audioPreview']);
      items.add(
        MediaItem(
          id: 'spotify-$trackId',
          title: title,
          creator: artist,
          category: 'Spotify import',
          kind: MediaKind.music,
          source: 'spotify:track:$trackId',
          color: 0xFFB8ABF5,
          art: items.length % 5,
          description:
              'Imported from Spotify playlist “$name”. Raaga plays Spotify preview audio when Spotify provides it.',
          durationMs: preview == null ? null : 30000,
          previewUrl: preview,
          externalUrl: 'https://open.spotify.com/track/$trackId',
        ),
      );
    }

    if (items.isEmpty) {
      throw const CatalogException(
        'Spotify returned this playlist, but no readable tracks were available.',
      );
    }

    return SpotifyPlaylistImport(
      id: id,
      name: name,
      owner: owner,
      sourceUrl: 'https://open.spotify.com/playlist/$id',
      items: items,
    );
  }

  Future<String?> fetchTrackPreview(String trackId) async {
    if (_previewCache.containsKey(trackId)) return _previewCache[trackId];
    if (!_playlistId.hasMatch(trackId)) return null;
    try {
      final response = await _client
          .get(
            Uri.parse('https://open.spotify.com/embed/track/$trackId'),
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
              'Accept': 'text/html,application/xhtml+xml',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        _previewCache[trackId] = null;
        return null;
      }
      final match = RegExp(
        r"""<script[^>]*id=["']__NEXT_DATA__["'][^>]*>(.*?)</script>""",
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(response.body);
      if (match == null) {
        _previewCache[trackId] = null;
        return null;
      }
      final data = jsonDecode(match.group(1)!.trim());
      final entity = _findMapWithKey(data, 'audioPreview');
      final preview = entity == null ? null : _httpsUrl(entity['audioPreview']);
      _previewCache[trackId] = preview;
      return preview;
    } catch (_) {
      _previewCache[trackId] = null;
      return null;
    }
  }

  static Map<String, dynamic>? _findTrackEntity(dynamic value) {
    if (value is Map) {
      final map = value.map((key, child) => MapEntry(key.toString(), child));
      if (map['trackList'] is List) return map;
      for (final child in map.values) {
        final found = _findTrackEntity(child);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final child in value) {
        final found = _findTrackEntity(child);
        if (found != null) return found;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _findMapWithKey(dynamic value, String key) {
    if (value is Map) {
      final map = value.map((k, child) => MapEntry(k.toString(), child));
      if (map.containsKey(key)) return map;
      for (final child in map.values) {
        final found = _findMapWithKey(child, key);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final child in value) {
        final found = _findMapWithKey(child, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String? _clean(dynamic value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String? _httpsUrl(dynamic value) {
    String? candidate;
    if (value is String) {
      candidate = value;
    } else if (value is Map) {
      final map = value.map((key, child) => MapEntry(key.toString(), child));
      candidate = _clean(map['url']);
      if (candidate == null) {
        for (final child in map.values) {
          final nested = _httpsUrl(child);
          if (nested != null) return nested;
        }
      }
    } else if (value is List) {
      for (final child in value) {
        final nested = _httpsUrl(child);
        if (nested != null) return nested;
      }
    }
    final uri = candidate == null ? null : Uri.tryParse(candidate);
    return uri?.scheme == 'https' && uri!.host.isNotEmpty ? candidate : null;
  }

  void dispose() => _client.close();
}
