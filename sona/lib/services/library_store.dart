import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

class LibrarySnapshot {
  LibrarySnapshot({
    Set<String>? likes,
    List<UserPlaylist>? playlists,
    Map<String, int>? progress,
    List<MediaItem>? items,
    List<PodcastFeed>? feeds,
    Map<String, String>? downloads,
    List<String>? history,
  }) : likes = likes ?? {},
       playlists = playlists ?? [],
       progress = progress ?? {},
       items = items ?? [],
       feeds = feeds ?? [],
       downloads = downloads ?? {},
       history = history ?? [];
  final Set<String> likes;
  final List<UserPlaylist> playlists;
  final Map<String, int> progress;
  final List<MediaItem> items;
  final List<PodcastFeed> feeds;
  final Map<String, String> downloads;
  final List<String> history;
  Map<String, dynamic> toJson() => {
    'likes': likes.toList(),
    'playlists': playlists.map((p) => p.toJson()).toList(),
    'progress': progress,
    'items': items.map((i) => i.toJson()).toList(),
    'feeds': feeds.map((f) => f.toJson()).toList(),
    'downloads': downloads,
    'history': history,
  };
  factory LibrarySnapshot.fromJson(
    Map<String, dynamic> data,
  ) => LibrarySnapshot(
    likes: Set<String>.from(data['likes'] as List? ?? []),
    playlists: (data['playlists'] as List? ?? [])
        .map((p) => UserPlaylist.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
    progress: Map<String, int>.from(data['progress'] as Map? ?? {}),
    items: (data['items'] as List? ?? [])
        .map((p) => MediaItem.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
    feeds: (data['feeds'] as List? ?? [])
        .map((p) => PodcastFeed.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
    downloads: Map<String, String>.from(data['downloads'] as Map? ?? {}),
    history: List<String>.from(data['history'] as List? ?? []),
  );
}

class LibraryStore {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  Future<void> _writes = Future<void>.value();
  static const _key = 'sona.library.v1';
  Future<LibrarySnapshot> read() async {
    final raw = await _prefs.getString(_key);
    return raw == null
        ? LibrarySnapshot()
        : LibrarySnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(LibrarySnapshot snapshot) {
    final encoded = jsonEncode(snapshot.toJson());
    final write = _writes.then((_) => _prefs.setString(_key, encoded));
    _writes = write.catchError((Object _) {});
    return write;
  }
}
